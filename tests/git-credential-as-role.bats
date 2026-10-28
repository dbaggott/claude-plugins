#!/usr/bin/env bats
#
# Tests for the push credential helper. Each test makes a real repository and a
# real `git worktree`, configures the worktree with the helper's own --install,
# the call `git-workflow` makes, and asks git itself through `git credential
# fill`. The resolver and the mint inside it are real, signing with a throwaway
# key; only the forge (gh, curl) is stubbed, as in as-role.bats.

bats_require_minimum_version 1.5.0
load role-tree

setup() {
  make_role_tree
  cp -R "$ROLE_ROOT/roles/author" "$TREE/roles/"
  stub_forge
  FULL_PERMS=$(jq -c '.required' "$ROLE_ROOT/roles/author/permissions.json"); export FULL_PERMS
  # The operator's own git credential, which the fallback hands on.
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
printf 'gh %s token=%s\n' "$*" "${GH_TOKEN:-none}" >> "$NET_LOG"
case "$*" in
  "api user"*) echo operator-login ;;
  "auth git-credential get")
    while IFS= read -r l && [ -n "$l" ]; do printf '%s\n' "$l" >> "$NET_LOG.in"; done
    printf 'username=operator-login\npassword=operator-secret\n' ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$STUB/gh"
  HELPER="$TREE/scripts/git-credential-as-role.sh"

  # No system or global config of the developer's may answer first, and git
  # must fail rather than prompt.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
  git config --global user.name t; git config --global user.email t@example.com
  # What `gh auth setup-git` writes, plus a plain helper: both must be cleared.
  printf '#!/bin/sh\necho "operator-helper $*" >> "%s"\nprintf "username=global\\npassword=global-secret\\n"\n' \
    "$NET_LOG" > "$STUB/global-helper"; chmod +x "$STUB/global-helper"
  git config --global credential.helper "$STUB/global-helper"
  git config --global credential.https://github.com.helper ''
  git config --global --add credential.https://github.com.helper "$STUB/global-helper"

  MAIN="$BATS_TEST_TMPDIR/repo"; WT="$BATS_TEST_TMPDIR/wt"
  git init -q "$MAIN"; git -C "$MAIN" commit -q --allow-empty -m init
}

origin() { git -C "$MAIN" remote add origin "$1"; git -C "$MAIN" worktree add -q "$WT" -b wt; }

fill() {  # <url-path> — git's own request, from inside the worktree
  printf 'protocol=https\nhost=github.com\npath=%s\n\n' "$1" | git -C "${2:-$WT}" credential fill
}

# --- install -----------------------------------------------------------------

@test "install configures the worktree alone; the main checkout keeps the operator's helpers" {
  origin https://github.com/acme/r.git
  run "$HELPER" --install author "$WT"
  [ "$output" = "result=OK worktree=$WT pushurl=origin" ]
  [ "$(git -C "$WT" config --worktree --get-all credential.helper | paste -sd'|' -)" = "|!\"$HELPER\" author" ]
  [ "$(git -C "$WT" config --worktree credential.useHttpPath)" = true ]
  ! git -C "$MAIN" config --worktree --get credential.helper
  run fill acme/r.git "$MAIN"
  [[ "$output" == *"password=global-secret"* ]]
}

@test "install is idempotent" {
  origin https://github.com/acme/r.git
  "$HELPER" --install author "$WT"
  "$HELPER" --install author "$WT"
  [ "$(git -C "$WT" config --worktree --get-all credential.helper | wc -l | tr -d ' ')" = 2 ]
}

@test "install refuses the main checkout, an unknown role and a non-repository" {
  origin https://github.com/acme/r.git
  run "$HELPER" --install author "$MAIN"
  [ "${lines[0]}" = "result=ERROR reason=main-worktree" ]
  ! git -C "$MAIN" config --get-all credential.helper
  run "$HELPER" --install nobody "$WT"
  [ "${lines[0]}" = "result=ERROR reason=unknown-role" ]
  run "$HELPER" --install author "$BATS_TEST_TMPDIR"
  [ "${lines[0]}" = "result=ERROR reason=not-a-worktree" ]
}

@test "install refuses a helper path the shell would read, writing nothing" {
  # The helper entry is `!"<path>" <role>`, evaluated by a shell.
  origin https://github.com/acme/r.git
  local c dir
  for c in '"' '$' '`' '\' $'\n'; do
    dir="$BATS_TEST_TMPDIR/plug${c}in"
    rm -rf "$dir"; cp -R "$TREE" "$dir"
    run "$dir/scripts/git-credential-as-role.sh" --install author "$WT"
    [ "${lines[0]}" = "result=ERROR reason=unsafe-helper-path" ]
    ! git -C "$WT" config --worktree --get-all credential.helper
  done
}

@test "an SSH origin gets an HTTPS push URL in the worktree, in both tiers, and fetches stay on SSH" {
  origin git@github.com:acme/r.git
  run "$HELPER" --install author "$WT"
  [ "$output" = "result=OK worktree=$WT pushurl=https://github.com/acme/r.git" ]
  [ "$(git -C "$WT" remote get-url --push origin)" = https://github.com/acme/r.git ]
  [ "$(git -C "$WT" remote get-url origin)" = git@github.com:acme/r.git ]
  [ "$(git -C "$MAIN" remote get-url --push origin)" = git@github.com:acme/r.git ]
  # Fallback: the push URL's credential comes through the helper, as the operator.
  run fill acme/r.git
  [[ "$output" == *"password=operator-secret"* ]]
  ! grep -q operator-helper "$NET_LOG"
  # Bot tier, configured after the worktree was made: the next fill uses it.
  configure_role author 7 agent-author-t
  run fill acme/r.git
  [[ "$output" == *"username=x-access-token"* ]]
  [[ "$output" == *"password=$STUB_TOKEN"* ]]
}

@test "an ssh:// origin is rewritten too" {
  origin ssh://git@github.com/acme/r.git
  run "$HELPER" --install author "$WT"
  [ "$output" = "result=OK worktree=$WT pushurl=https://github.com/acme/r.git" ]
}

# --- get ---------------------------------------------------------------------

@test "a configured author answers with a token minted for that repo, and nothing is written" {
  origin https://github.com/acme/r.git
  "$HELPER" --install author "$WT"
  configure_role author 7 agent-author-t
  run --separate-stderr fill acme/r.git
  [ "$status" -eq 0 ]
  [[ "$output" == *"username=x-access-token"* ]]
  [[ "$output" == *"password=$STUB_TOKEN"* ]]
  [[ "$stderr" == *"as-role.sh: result=OK as=agent-author-t fallback=none"* ]]
  # The installation came from the repo's owner, not the bare host.
  grep -q '/app/installations' "$NET_LOG"
  ! grep -q operator-helper "$NET_LOG"
  # The token is in no config and no file.
  ! git -C "$WT" config --list --show-origin | grep -qF "$STUB_TOKEN"
  ! grep -rqF "$STUB_TOKEN" "$MAIN/.git" "$HOME"
}

@test "an author with no App answers with the operator's gh credential" {
  origin https://github.com/acme/r.git
  "$HELPER" --install author "$WT"
  run --separate-stderr fill acme/r.git
  [ "$status" -eq 0 ]
  [[ "$output" == *"username=operator-login"* ]]
  [[ "$output" == *"password=operator-secret"* ]]
  [[ "$stderr" == *"as-role.sh: result=OK as=operator-login fallback=unconfigured"* ]]
  grep -q '^gh auth git-credential get token=none' "$NET_LOG"
  grep -qx 'host=github.com' "$NET_LOG.in"
  ! grep -q operator-helper "$NET_LOG"
}

@test "a configured author whose mint fails is an error, never the operator's credential" {
  origin https://github.com/acme/r.git
  "$HELPER" --install author "$WT"
  local dir="$XDG_CONFIG_HOME/dnbg/author"; mkdir -p "$dir"; chmod 700 "$dir"
  echo '{"app_id":"7","slug":"agent-author-t","private_key_command":"exit 3"}' > "$dir/config.json"
  chmod 600 "$dir/config.json"
  run --separate-stderr fill acme/r.git
  [ "$status" -ne 0 ]
  [[ "$output" != *"password="* ]]
  [[ "$stderr" == *"reason=credential"* ]]
  ! grep -q 'auth git-credential' "$NET_LOG"
  ! grep -q operator-helper "$NET_LOG"
}

@test "with no repository path, the helper stops git rather than guessing an installation" {
  origin https://github.com/acme/r.git
  "$HELPER" --install author "$WT"
  git -C "$WT" config --worktree credential.useHttpPath false
  configure_role author 7 agent-author-t
  run --separate-stderr fill acme/r.git
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"useHttpPath"* ]]
  ! grep -q '^curl' "$NET_LOG"
}

@test "store and erase keep nothing" {
  run sh -c 'printf "protocol=https\nhost=github.com\npassword=x\n\n" | "$1" author store' _ "$HELPER"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  run sh -c 'printf "protocol=https\nhost=github.com\n\n" | "$1" author erase' _ "$HELPER"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

# --- what would still skip the helper ----------------------------------------

@test "a shared SSH push URL is refused, not added beside" {
  origin https://github.com/acme/r.git
  git -C "$MAIN" config remote.origin.pushurl git@github.com:acme/r.git
  run "$HELPER" --install author "$WT"
  [ "${lines[0]}" = "result=ERROR reason=push-not-https" ]
  [ "$(git -C "$WT" remote get-url --push --all origin | wc -l | tr -d ' ')" = 1 ]
}

@test "an insteadOf rule turning the HTTPS push URL back into SSH is refused" {
  origin git@github.com:acme/r.git
  git config --global url."git@github.com:".insteadOf https://github.com/
  run "$HELPER" --install author "$WT"
  [ "${lines[0]}" = "result=ERROR reason=push-not-https" ]
}

@test "an SSH host alias is refused rather than turned into a host that does not exist" {
  origin git@github-work:acme/r.git
  run "$HELPER" --install author "$WT"
  [ "${lines[0]}" = "result=ERROR reason=push-not-https" ]
}

@test "a bare repository's worktree is refused before the extension changes it" {
  git init -q --bare "$BATS_TEST_TMPDIR/b.git"
  git -C "$MAIN" push -q "$BATS_TEST_TMPDIR/b.git" HEAD:main
  git -C "$BATS_TEST_TMPDIR/b.git" remote add origin https://github.com/acme/r.git
  git -C "$BATS_TEST_TMPDIR/b.git" worktree add -q "$BATS_TEST_TMPDIR/bwt" main
  run "$HELPER" --install author "$BATS_TEST_TMPDIR/bwt"
  [ "${lines[0]}" = "result=ERROR reason=bare-repo" ]
  [ -z "$(git -C "$BATS_TEST_TMPDIR/b.git" config --get extensions.worktreeConfig)" ]
  git -C "$BATS_TEST_TMPDIR/bwt" status >/dev/null
}

# Claude Code's sandbox refuses .git/config even inside the working directory,
# while the worktree's own config under .git/worktrees/ can stay writable.
@test "an unwritable shared config is reported by its path, with the sandbox as a likely cause" {
  origin https://github.com/acme/r.git
  chmod a-w "$MAIN/.git"
  run --separate-stderr "$HELPER" --install author "$WT"
  chmod u+w "$MAIN/.git"
  [ "$output" = "result=ERROR reason=git-config" ]
  [[ "$stderr" == *"could not write $(cd "$MAIN/.git" && pwd -P)/config,"* ]]
  [[ "$stderr" == *"could not lock config file"* ]]
  [[ "$stderr" == *"sandbox"* ]]
}

@test "with the extension already set, an unwritable shared config does not stop the install" {
  origin https://github.com/acme/r.git
  git -C "$MAIN" config extensions.worktreeConfig true
  chmod a-w "$MAIN/.git"
  run "$HELPER" --install author "$WT"
  chmod u+w "$MAIN/.git"
  [ "$output" = "result=OK worktree=$WT pushurl=origin" ]
  [ "$(git -C "$WT" config --worktree credential.useHttpPath)" = true ]
}

@test "an unwritable worktree config is reported by its path" {
  origin https://github.com/acme/r.git
  chmod a-w "$MAIN/.git/worktrees/wt"
  run --separate-stderr "$HELPER" --install author "$WT"
  chmod u+w "$MAIN/.git/worktrees/wt"
  [ "$output" = "result=ERROR reason=git-config" ]
  [[ "$stderr" == *"could not write $(cd "$MAIN/.git/worktrees/wt" && pwd -P)/config.worktree,"* ]]
}

@test "a Git LFS request is answered for the repository it belongs to" {
  origin https://github.com/acme/r.git
  "$HELPER" --install author "$WT"
  configure_role author 7 agent-author-t
  run --separate-stderr fill acme/r.git/info/lfs
  [ "$status" -eq 0 ]
  [[ "$output" == *"password=$STUB_TOKEN"* ]]
}
