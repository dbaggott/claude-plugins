#!/usr/bin/env bats
#
# Tests for role App setup. bootstrap.py runs in a copy of the plugin beside
# fixture roles (role-tree.bash), with GitHub's half of the Manifest flow and the
# browser click replaced by fixtures/bootstrap/drive.py, so what is under test is
# the loop over roles: which it creates, from which permissions, into which dir.

load role-tree

setup() {
  make_role_tree
  add_role author operator
  MANIFESTS="$BATS_TEST_TMPDIR/manifests"; : > "$MANIFESTS"
  PORT=$((20000 + RANDOM % 20000))
}

bootstrap() {
  run python3 "$BATS_TEST_DIRNAME/fixtures/bootstrap/drive.py" \
    "$TREE/skills/reviewer-setup" "$MANIFESTS" --port "$PORT" --timeout 20 "$@"
}

@test "a chosen subset of roles each gets its own App, in its own config dir" {
  bootstrap --roles reviewer,author
  [ "$status" -eq 0 ]
  [ "$(jq -r '.slug' "$XDG_CONFIG_HOME/dnbg/reviewer/config.json")" = agent-reviewer-tester ]
  [ "$(jq -r '.slug' "$XDG_CONFIG_HOME/dnbg/author/config.json")" = agent-author-tester ]
  [ "$(cat "$XDG_CONFIG_HOME/dnbg/author/private-key.pem")" = "PEM for agent-author-tester" ]
  [ "$(find -L "$XDG_CONFIG_HOME/dnbg/author" -maxdepth 0 -perm 700 | wc -l)" -eq 1 ]
}

@test "each manifest carries its own role's permissions" {
  bootstrap --roles reviewer,author
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p "$MANIFESTS" | jq -c .default_permissions)" = "$(jq -c .required "$TREE/roles/reviewer/permissions.json")" ]
  [ "$(sed -n 2p "$MANIFESTS" | jq -c .default_permissions)" = "$(jq -c .required "$TREE/roles/author/permissions.json")" ]
}

@test "a role left out is not created" {
  bootstrap --roles author
  [ "$status" -eq 0 ]
  [ -f "$XDG_CONFIG_HOME/dnbg/author/config.json" ]
  [ ! -e "$XDG_CONFIG_HOME/dnbg/reviewer" ]
  [ "$(wc -l < "$MANIFESTS")" -eq 1 ]
}

@test "by default every role not yet set up is created, and the rest skipped" {
  mkdir -p "$XDG_CONFIG_HOME/dnbg/reviewer"; echo '{"slug":"existing"}' > "$XDG_CONFIG_HOME/dnbg/reviewer/config.json"
  bootstrap
  [ "$status" -eq 0 ]
  [ "$(jq -r .slug "$XDG_CONFIG_HOME/dnbg/reviewer/config.json")" = existing ]
  [ "$(jq -r .slug "$XDG_CONFIG_HOME/dnbg/author/config.json")" = agent-author-tester ]
}

@test "an unknown role is refused before any App is created" {
  bootstrap --roles author,nobody
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown role(s) nobody"* ]]
  [ ! -s "$MANIFESTS" ]
}

@test "--name applies to one role only" {
  bootstrap --roles reviewer,author --name x
  [ "$status" -eq 2 ]
  [ ! -s "$MANIFESTS" ]
}

@test "a role set up through its variables alone counts as set up" {
  export DNBG_REVIEWER_APP_ID=42
  bootstrap
  [ "$status" -eq 0 ]
  [ ! -e "$XDG_CONFIG_HOME/dnbg/reviewer" ]
  [ -f "$XDG_CONFIG_HOME/dnbg/author/config.json" ]
}

@test "a config dir under ~/ is read from \$HOME" {
  export HOME="$BATS_TEST_TMPDIR/home" DNBG_AUTHOR_CONFIG_DIR='~/author'
  bootstrap --roles author
  [ "$status" -eq 0 ]
  [ -f "$HOME/author/config.json" ]
}

@test "a ~user config dir is refused before any App is created" {
  export DNBG_AUTHOR_CONFIG_DIR='~alice/author'
  bootstrap --roles reviewer,author
  [ "$status" -ne 0 ]
  [[ "$output" == *"DNBG_AUTHOR_CONFIG_DIR is '~alice/author'"* ]]
  [ ! -s "$MANIFESTS" ]
}

@test "a role directory the resolver would refuse is not set up" {
  mkdir -p "$TREE/roles/Odd_Name"; cp "$TREE/roles/author/permissions.json" "$TREE/roles/Odd_Name/"
  bootstrap --roles Odd_Name
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown role(s) Odd_Name"* ]]
}
