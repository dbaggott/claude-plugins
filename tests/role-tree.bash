# shellcheck shell=bash
# A copy of the plugin's scripts and hooks beside a roles/ directory of the
# test's choosing. The resolver finds roles relative to itself, so a test gets
# its own role set by running the copy, with no override in the shipped code.
#
#   make_role_tree             -> TREE, with the real reviewer role
#   add_role <name> <fallback> -> a fixture role; fallback operator|refuse|''
#   ship_role <name>           -> the plugin's own data for that role
#   stub_forge                 -> STUB on PATH: gh and curl answering as GitHub
#   configure_role <role> <app-id> <slug>  -> a config dir with a real key
#
# The environment is cleared of every DNBG_* variable and points
# XDG_CONFIG_HOME at the test's own directory, so a developer's real setup
# cannot leak into an assertion.

ROLE_ROOT="${BATS_TEST_DIRNAME}/../dnbg-workflow"

make_role_tree() {
  local v
  for v in $(compgen -v DNBG_); do unset "$v"; done
  unset GH_TOKEN GITHUB_TOKEN
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/xdg"; mkdir -p "$XDG_CONFIG_HOME"

  TREE="$BATS_TEST_TMPDIR/tree"
  mkdir -p "$TREE/scripts" "$TREE/hooks" "$TREE/roles" "$TREE/skills/reviewer-setup"
  cp "$ROLE_ROOT"/scripts/*.sh "$TREE/scripts/"
  cp "$ROLE_ROOT"/hooks/*.sh "$TREE/hooks/"
  cp "$ROLE_ROOT/skills/reviewer-setup/bootstrap.py" "$TREE/skills/reviewer-setup/"
  cp -R "$ROLE_ROOT/roles/reviewer" "$TREE/roles/"
}

ship_role() {  # <name>
  cp -R "$ROLE_ROOT/roles/$1" "$TREE/roles/"
}

add_role() {  # <name> <fallback>
  mkdir -p "$TREE/roles/$1"
  jq -n --arg f "$2" '{required: {issues: "write", metadata: "read"}}
    + (if $f == "" then {} else {fallback: $f} end)' > "$TREE/roles/$1/permissions.json"
}

# `gh` answers `api user` with the operator's login and records each call with
# the credential it ran under; `curl` is the App API the mint talks to.
stub_forge() {
  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  export NET_LOG="$BATS_TEST_TMPDIR/net"; : > "$NET_LOG"
  export STUB_TOKEN="ghs_stub_$RANDOM$RANDOM"
  FULL_PERMS=$(jq -c '.required' "$ROLE_ROOT/roles/reviewer/permissions.json")
  export FULL_PERMS
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
printf 'gh %s token=%s\n' "$*" "${GH_TOKEN:-none}" >> "$NET_LOG"
case "$1 $2" in
  "api user") echo operator-login ;;
  "api graphql") cat "${GQL:-/dev/null}" ;;
  "issue comment") echo "https://github.com/acme/r/issues/7#issuecomment-1" ;;
esac
EOF
  cat > "$STUB/curl" <<'EOF'
#!/usr/bin/env bash
printf 'curl %s\n' "${*: -1}" >> "$NET_LOG"
for a in "$@"; do
  case "$a" in
    *"/access_tokens") echo "{\"token\":\"$STUB_TOKEN\",\"permissions\":$FULL_PERMS}"; exit 0 ;;
    *"/app/installations") echo '[{"id":123,"account":{"login":"acme"}}]'; exit 0 ;;
  esac
done
exit 1
EOF
  chmod +x "$STUB/gh" "$STUB/curl"
  export PATH="$STUB:$PATH"
}

configure_role() {  # <role> <app-id> <slug>
  local dir="$XDG_CONFIG_HOME/dnbg/$1"
  mkdir -p "$dir"; chmod 700 "$dir"
  openssl genrsa -out "$dir/private-key.pem" 2048 2>/dev/null
  chmod 600 "$dir/private-key.pem"
  jq -n --arg id "$2" --arg s "$3" '{app_id: $id, slug: $s}' > "$dir/config.json"
  chmod 600 "$dir/config.json"
}
