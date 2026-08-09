#!/usr/bin/env bats
#
# Tests for where the reviewer bot's private key comes from, and for the two
# properties that make the key-command hook safe to have at all:
#
#   - a repository cannot influence which command runs;
#   - the key never lands on disk on the way to `openssl`.
#
# The signing is real — a throwaway RSA key is generated per test and the JWT is
# actually signed — because the whole point of the resolution order is that each
# source produces a key openssl accepts. Only the network is stubbed.

MINT="${BATS_TEST_DIRNAME}/../dnbg-workflow/skills/reviewer/mint-token.sh"

setup() {
  # Cleared here rather than with `env -u` at the call site, for two reasons: a
  # developer's real DNBG_REVIEWER_* would otherwise invalidate every assertion,
  # and passing the PEM as an `env` operand puts the key in the command line bats
  # echoes on failure. Tests that want a variable export it themselves; bats runs
  # each test in its own process, so nothing leaks between them.
  unset DNBG_REVIEWER_PRIVATE_KEY DNBG_REVIEWER_PRIVATE_KEY_COMMAND \
        DNBG_REVIEWER_APP_ID DNBG_REVIEWER_INSTALLATION_ID

  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  CONFDIR="$BATS_TEST_TMPDIR/conf"; mkdir -p "$CONFDIR"; chmod 700 "$CONFDIR"
  KEYFILE="$BATS_TEST_TMPDIR/key.pem"
  openssl genrsa -out "$KEYFILE" 2048 2>/dev/null
  chmod 600 "$KEYFILE"

  # A private TMPDIR per test, so "did anything write the key to disk" is
  # answerable by looking at one directory rather than guessing at /tmp.
  PRIVTMP="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$PRIVTMP"

  # Stubbed GitHub. Matches on the URL rather than argument position, because the
  # token call adds `-X POST` ahead of it.
  cat > "$STUB/curl" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
  case "$a" in
    *"/access_tokens") echo '{"token":"ghs_stubbed_token"}'; exit 0 ;;
    *"/app/installations") echo '[{"id":123,"account":{"login":"acme"}}]'; exit 0 ;;
  esac
done
exit 1
EOF
  chmod +x "$STUB/curl"
}

# Run the script with the stub prepended and a private TMPDIR, inheriting
# whatever DNBG_REVIEWER_* the test has exported.
mint() {
  run env PATH="$STUB:$PATH" TMPDIR="$PRIVTMP" DNBG_REVIEWER_CONFIG_DIR="$CONFDIR" \
    bash "$MINT" acme
}

write_config() { printf '%s\n' "$1" > "$CONFDIR/config.json"; chmod 600 "$CONFDIR/config.json"; }

# --- the three sources -------------------------------------------------------

@test "the env-var route mints with no config file and no PEM at all" {
  # The headless/CI case. Nothing in the config dir — this must stand alone
  # rather than supplement an existing workstation setup.
  export DNBG_REVIEWER_APP_ID=42
  export DNBG_REVIEWER_PRIVATE_KEY="$(cat "$KEYFILE")"
  mint
  [ "$status" -eq 0 ]
  [ "$output" = "ghs_stubbed_token" ]
  [ -z "$(ls -A "$CONFDIR")" ]
}

@test "a key command mints with no PEM in the config dir" {
  write_config '{"app_id":"42","private_key_command":"cat '"$KEYFILE"'"}'
  mint
  [ "$status" -eq 0 ]
  [ "$output" = "ghs_stubbed_token" ]
  [ ! -f "$CONFDIR/private-key.pem" ]
}

@test "the key command may also come from the environment" {
  write_config '{"app_id":"42"}'
  export DNBG_REVIEWER_PRIVATE_KEY_COMMAND="cat $KEYFILE"
  mint
  [ "$status" -eq 0 ]
  [ "$output" = "ghs_stubbed_token" ]
}

@test "the PEM file still works, and is the last resort" {
  cp "$KEYFILE" "$CONFDIR/private-key.pem"; chmod 600 "$CONFDIR/private-key.pem"
  write_config '{"app_id":"42"}'
  mint
  [ "$status" -eq 0 ]
  [ "$output" = "ghs_stubbed_token" ]
}

@test "resolution order is env, then command, then file" {
  # Every source present and only one of them valid: whichever the script picks
  # is the one that signs, so the order is observable from the outcome.
  cp "$KEYFILE" "$CONFDIR/private-key.pem"; chmod 600 "$CONFDIR/private-key.pem"
  write_config '{"app_id":"42","private_key_command":"echo not-a-key"}'
  # env beats the (broken) command
  export DNBG_REVIEWER_PRIVATE_KEY="$(cat "$KEYFILE")"
  mint
  [ "$status" -eq 0 ]
  # ...and with env gone, the broken command beats the good file, so this fails
  # rather than silently falling through to the PEM.
  unset DNBG_REVIEWER_PRIVATE_KEY
  mint
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a usable RSA private key"* ]]
}

# --- the property the feature's safety rests on ------------------------------

@test "a repo-local config file cannot influence which command runs" {
  # `credential.helper`'s failure mode: a value supplied by a checked-out repo
  # becoming command execution. Nothing here may read config from the working
  # directory, so a config.json sitting in cwd must be inert.
  local repo="$BATS_TEST_TMPDIR/repo"; mkdir -p "$repo/.dnbg"
  local marker="$BATS_TEST_TMPDIR/PWNED"
  local evil='{"app_id":"666","private_key_command":"touch '"$marker"'; cat '"$KEYFILE"'"}'
  printf '%s\n' "$evil" > "$repo/config.json"
  printf '%s\n' "$evil" > "$repo/.dnbg/config.json"

  cp "$KEYFILE" "$CONFDIR/private-key.pem"; chmod 600 "$CONFDIR/private-key.pem"
  write_config '{"app_id":"42"}'

  cd "$repo"
  mint
  [ "$status" -eq 0 ]
  [ ! -e "$marker" ]
}

# --- the key must not reach disk ---------------------------------------------

@test "no file containing the key is left behind after a run" {
  write_config '{"app_id":"42","private_key_command":"cat '"$KEYFILE"'"}'
  mint
  [ "$status" -eq 0 ]
  # The private TMPDIR is where a mktemp implementation would have put it.
  [ -z "$(ls -A "$PRIVTMP")" ]
  # Belt and braces: nothing anywhere under the test dir carries the key body,
  # apart from the fixture itself.
  local body; body=$(sed -n '2p' "$KEYFILE")
  run grep -rl --fixed-strings "$body" "$BATS_TEST_TMPDIR"
  [ "$output" = "$KEYFILE" ]
}

@test "an interrupted run leaves nothing behind either" {
  # The case a mktemp+trap implementation has to get exactly right and this one
  # gets structurally: there is no path on disk to clean up, so the signal cannot
  # strand anything. A slow key command holds the run open to be interrupted.
  write_config '{"app_id":"42","private_key_command":"sleep 5; cat '"$KEYFILE"'"}'
  env PATH="$STUB:$PATH" TMPDIR="$PRIVTMP" DNBG_REVIEWER_CONFIG_DIR="$CONFDIR" \
    bash "$MINT" acme >/dev/null 2>&1 &
  local pid=$! i=0
  while [ "$i" -lt 20 ] && ! pgrep -P "$pid" >/dev/null 2>&1; do sleep 0.1; i=$((i + 1)); done
  kill -INT "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null || true
  [ -z "$(ls -A "$PRIVTMP")" ]
}

# --- directory hardening -----------------------------------------------------

@test "a world-writable config dir is refused, naming the problem" {
  cp "$KEYFILE" "$CONFDIR/private-key.pem"; chmod 600 "$CONFDIR/private-key.pem"
  write_config '{"app_id":"42"}'
  chmod 777 "$CONFDIR"
  mint
  [ "$status" -ne 0 ]
  [[ "$output" == *"group- or world-writable"* ]]
  [[ "$output" == *"$CONFDIR"* ]]
}

@test "a group-writable PEM is refused even in a good directory" {
  # 0600 on the file is what bootstrap.py writes; this is the case where someone
  # has since loosened it. The key can then be replaced, which is the whole risk.
  cp "$KEYFILE" "$CONFDIR/private-key.pem"; chmod 660 "$CONFDIR/private-key.pem"
  write_config '{"app_id":"42"}'
  mint
  [ "$status" -ne 0 ]
  [[ "$output" == *"group- or world-writable"* ]]
}

@test "permissions are not checked on a route that does not read the dir" {
  # A loose config dir is irrelevant when the key comes from the environment and
  # nothing in that directory is consulted. Refusing there would break the
  # headless path for a directory it never touches.
  chmod 777 "$CONFDIR"
  export DNBG_REVIEWER_APP_ID=42
  export DNBG_REVIEWER_PRIVATE_KEY="$(cat "$KEYFILE")"
  mint
  [ "$status" -eq 0 ]
  [ "$output" = "ghs_stubbed_token" ]
}

# --- failure messages --------------------------------------------------------

@test "no key from any source reports what was tried" {
  write_config '{"app_id":"42"}'
  mint
  [ "$status" -ne 0 ]
  [[ "$output" == *"DNBG_REVIEWER_PRIVATE_KEY"* ]]
  [[ "$output" == *"private-key.pem"* ]]
}

@test "a missing app_id points at both the setup and the headless variable" {
  export DNBG_REVIEWER_PRIVATE_KEY="$(cat "$KEYFILE")"
  mint
  [ "$status" -ne 0 ]
  [[ "$output" == *"DNBG_REVIEWER_APP_ID"* ]]
}

@test "a failing key command is reported as such, not as a missing key" {
  write_config '{"app_id":"42","private_key_command":"exit 3"}'
  mint
  [ "$status" -ne 0 ]
  [[ "$output" == *"key command failed"* ]]
}
