#!/usr/bin/env bats
#
# Tests for the role resolver and the SessionStart notice built on it. Each test
# runs a copy of the scripts beside its own roles/ (role-tree.bash), with the
# forge stubbed; the mint inside is real, signing with a throwaway key.

bats_require_minimum_version 1.5.0
load role-tree

setup() {
  make_role_tree
  stub_forge
  AS="$TREE/scripts/as-role.sh"
  add_role author operator
  add_role orchestrator operator
}

# --- credential --------------------------------------------------------------

@test "a configured role runs the command with its token, and says as whom" {
  configure_role reviewer 42 agent-reviewer-t
  run --separate-stderr "$AS" reviewer acme/r -- sh -c 'echo "token=$GH_TOKEN"'
  [ "$status" -eq 0 ]
  [ "$output" = "token=$STUB_TOKEN" ]
  [ "$stderr" = "as-role.sh: result=OK as=agent-reviewer-t fallback=none" ]
}

@test "the token is scoped to the repo's owner" {
  configure_role reviewer 42 agent-reviewer-t
  run "$AS" reviewer acme/r -- true
  [ "$status" -eq 0 ]
  run "$AS" reviewer elsewhere/r -- true
  [ "$status" -eq 125 ]
  [[ "$output" == *"not installed on 'elsewhere'"* ]]
}

@test "the command's stdin and exit status are its own" {
  configure_role reviewer 42 agent-reviewer-t
  run sh -c 'echo piped | "$1" reviewer acme/r -- cat' _ "$AS"
  [[ "$output" == *piped* ]]
  run "$AS" reviewer acme/r -- sh -c 'exit 7'
  [ "$status" -eq 7 ]
}

@test "no token reaches stdout, stderr, git config or any file" {
  configure_role reviewer 42 agent-reviewer-t
  local repo="$BATS_TEST_TMPDIR/repo"
  git init -q "$repo"
  cd "$repo"
  run "$AS" reviewer acme/r -- sh -c 'echo ran; git config --list'
  [ "$status" -eq 0 ]
  [[ "$output" == *ran* ]]
  [[ "$output" != *"$STUB_TOKEN"* ]]
  run grep -rl --fixed-strings "$STUB_TOKEN" "$BATS_TEST_TMPDIR"
  [ "$status" -eq 1 ]
}

@test "a token already in the environment is replaced, not inherited" {
  configure_role reviewer 42 agent-reviewer-t
  GH_TOKEN=stale GITHUB_TOKEN=stale2 run "$AS" reviewer acme/r -- sh -c 'echo "$GH_TOKEN ${GITHUB_TOKEN:-unset}"'
  [[ "$output" == *"$STUB_TOKEN unset"* ]]
}

# --- login and operator ------------------------------------------------------

@test "--login answers a configured role's App slug, with no network call" {
  configure_role reviewer 42 agent-reviewer-t
  run "$AS" --login reviewer acme/r
  [ "$output" = "result=OK login=agent-reviewer-t fallback=none" ]
  [ ! -s "$NET_LOG" ]
}

@test "--login reads the slug from the environment on a headless setup" {
  export DNBG_REVIEWER_APP_ID=42 DNBG_REVIEWER_SLUG=agent-reviewer-h
  run "$AS" --login reviewer acme/r
  [ "$output" = "result=OK login=agent-reviewer-h fallback=none" ]
}

@test "--login without a known slug says so rather than answering empty" {
  export DNBG_REVIEWER_APP_ID=42
  run "$AS" --login reviewer acme/r
  [ "${lines[0]}" = "result=ERROR reason=no-login" ]
}

@test "--operator reads the operator's login with no role token in place" {
  GH_TOKEN=leaked run "$AS" --operator acme/r
  [ "$output" = "result=OK login=operator-login fallback=none" ]
  grep -qx 'gh api user --jq .login token=none' "$NET_LOG"
}

# --- fallback (R16, R17) -----------------------------------------------------

@test "an unconfigured role that may fall back runs as the operator, and says so" {
  GH_TOKEN=leaked run --separate-stderr "$AS" author acme/r -- sh -c 'echo "token=${GH_TOKEN:-none}"'
  [ "$status" -eq 0 ]
  [ "$output" = "token=none" ]
  [ "$stderr" = "as-role.sh: result=OK as=operator-login fallback=unconfigured" ]
  run "$AS" --login author acme/r
  [ "$output" = "result=OK login=operator-login fallback=unconfigured" ]
}

@test "the unconfigured reviewer is an error, and the command never runs" {
  run "$AS" reviewer acme/r -- touch "$BATS_TEST_TMPDIR/ran"
  [ "$status" -eq 125 ]
  [[ "$output" == *"result=ERROR reason=not-configured"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/ran" ]
  run "$AS" --login reviewer acme/r
  [ "${lines[0]}" = "result=ERROR reason=not-configured" ]
}

@test "a role with no fallback key refuses, as the default" {
  add_role planner ""
  run "$AS" planner acme/r -- true
  [ "$status" -eq 125 ]
  [[ "$output" == *"reason=not-configured"* ]]
}

@test "a configured role whose key command fails is an error, never the operator" {
  local dir="$XDG_CONFIG_HOME/dnbg/author"; mkdir -p "$dir"; chmod 700 "$dir"
  echo '{"app_id":"7","slug":"agent-author-t","private_key_command":"exit 3"}' > "$dir/config.json"
  chmod 600 "$dir/config.json"
  run "$AS" author acme/r -- touch "$BATS_TEST_TMPDIR/ran"
  [ "$status" -eq 125 ]
  [[ "$output" == *"reason=credential"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/ran" ]
  ! grep -q '^gh ' "$NET_LOG"
}

@test "a configured role whose key command prints nothing is an error too" {
  export DNBG_AUTHOR_APP_ID=7 DNBG_AUTHOR_PRIVATE_KEY_COMMAND=true
  run "$AS" author acme/r -- touch "$BATS_TEST_TMPDIR/ran"
  [ "$status" -eq 125 ]
  [[ "$output" == *"produced no output"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/ran" ]
}

@test "two roles configured with one App fail every call" {
  configure_role reviewer 42 agent-reviewer-t
  export DNBG_AUTHOR_CONFIG_DIR="$XDG_CONFIG_HOME/dnbg/reviewer"
  run "$AS" reviewer acme/r -- touch "$BATS_TEST_TMPDIR/ran"
  [ "$status" -eq 125 ]
  [[ "$output" == *"reason=shared-identity"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/ran" ]
  run "$AS" --login author acme/r
  [ "${lines[0]}" = "result=ERROR reason=shared-identity" ]
}

@test "author and orchestrator may both fall back to the operator" {
  run "$AS" --login author acme/r
  [ "$output" = "result=OK login=operator-login fallback=unconfigured" ]
  run "$AS" --login orchestrator acme/r
  [ "$output" = "result=OK login=operator-login fallback=unconfigured" ]
}

# --- arguments ---------------------------------------------------------------

@test "owner/name is short for github.com, and remote URLs resolve the same" {
  configure_role reviewer 42 agent-reviewer-t
  local spec
  for spec in acme/r github.com/acme/r https://github.com/acme/r.git \
              git@github.com:acme/r.git ssh://git@github.com/acme/r; do
    run "$AS" --login reviewer "$spec"
    [ "$output" = "result=OK login=agent-reviewer-t fallback=none" ] || { echo "$spec: $output"; false; }
  done
}

@test "a bare owner is refused" {
  run "$AS" --login reviewer acme
  [ "${lines[0]}" = "result=ERROR reason=bad-repo" ]
  run "$AS" reviewer acme -- true
  [ "$status" -eq 125 ]
  [[ "$output" == *"reason=bad-repo"* ]]
}

@test "another forge is refused until it has a backend, and GitHub does not nest" {
  run "$AS" --operator gitlab.com/group/sub/r
  [ "${lines[0]}" = "result=ERROR reason=unsupported-forge" ]
  run "$AS" --operator github.com/a/b/c
  [ "${lines[0]}" = "result=ERROR reason=bad-repo" ]
}

@test "an unknown role, or role data with a bad fallback, is refused" {
  run "$AS" --login nobody acme/r
  [ "${lines[0]}" = "result=ERROR reason=unknown-role" ]
  add_role odd sometimes
  run "$AS" --login odd acme/r
  [ "${lines[0]}" = "result=ERROR reason=bad-role-data" ]
}

@test "the credential form needs -- and a command" {
  run "$AS" reviewer acme/r
  [ "$status" -eq 125 ]
  run "$AS" reviewer acme/r true
  [ "$status" -eq 125 ]
  [[ "$output" == *"reason=bad-args"* ]]
}

# --- fallbacks and the SessionStart notice (R18) -----------------------------

@test "--fallbacks names each role that would act as the operator" {
  run "$AS" --fallbacks
  [ "$output" = "result=OK roles=author,orchestrator" ]
  configure_role author 7 agent-author-t
  run "$AS" --fallbacks
  [ "$output" = "result=OK roles=orchestrator" ]
  [ ! -s "$NET_LOG" ]
}

@test "the notice names each falling-back role, with no network call" {
  run "$TREE/hooks/role-fallback-notice.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"post under your"*"author, orchestrator"* ]]
  [ ! -s "$NET_LOG" ]
}

@test "the notice is silent when nothing falls back" {
  rm -r "$TREE/roles/author" "$TREE/roles/orchestrator"
  run "$TREE/hooks/role-fallback-notice.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "the shipped roles print no notice, set up or not" {
  run "$ROLE_ROOT/hooks/role-fallback-notice.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "the notice reports two roles sharing one App" {
  configure_role author 7 agent-author-t
  export DNBG_ORCHESTRATOR_CONFIG_DIR="$XDG_CONFIG_HOME/dnbg/author"
  run "$TREE/hooks/role-fallback-notice.sh"
  [[ "$output" == *"two roles share one GitHub App"* ]]
}
