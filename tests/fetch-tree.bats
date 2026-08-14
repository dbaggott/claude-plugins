#!/usr/bin/env bats
#
# Tests for the whole-tree fetch. `gh` is stubbed on PATH and emits whatever the
# test asked for — a real tarball, a 404 body, or a failure — so every branch is
# reachable without a network.
#
# What matters is that an empty tree never reaches the caller as an answer, and
# two different failures produce one: a bad SHA, which fails the pipeline and
# reports `reason=fetch`, and an archive with no members, where both sides of the
# pipe exit 0 and only the file count catches it. Both are covered below.
# Measured before the script existed: the inline snippet it replaces left a
# zero-file directory on a bad SHA and nothing downstream read the exit code, so
# a repo-wide sweep over that directory came back clean.

FETCH="${BATS_TEST_DIRNAME}/../dnbg-workflow/scripts/fetch-tree.sh"

setup() {
  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  export MODE="$BATS_TEST_TMPDIR/mode"
  export FIXTURE="$BATS_TEST_TMPDIR/fixture.tar.gz"

  # A tarball shaped like GitHub's: every path under one <owner>-<repo>-<sha>/
  # wrapper, which --strip-components=1 removes.
  local src="$BATS_TEST_TMPDIR/src/acme-repo-abc123"
  mkdir -p "$src/dnbg-workflow/skills"
  echo 'needle' > "$src/README.md"
  echo 'other'  > "$src/dnbg-workflow/skills/SKILL.md"
  tar cz -C "$BATS_TEST_TMPDIR/src" -f "$FIXTURE" acme-repo-abc123

  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
case "$(cat "$MODE")" in
  ok)    cat "$FIXTURE" ;;
  # What the API actually returns for an unknown ref: a JSON error body, exit 1.
  bad)   echo '{"message":"Not Found"}'; exit 1 ;;
  # A 200 that yields no members — a valid archive of nothing.
  hollow) tar cz -T /dev/null ;;
esac
EOF
  chmod +x "$STUB/gh"
  export PATH="$STUB:$PATH"
  echo ok > "$MODE"
}

field() { sed -n "s/.*[ ]$1=\([^ ]*\).*/\1/p" <<<"$2"; }

@test "a good SHA extracts the tree and reports where it went" {
  run "$FETCH" acme/repo abc123
  [ "$status" -eq 0 ]
  [[ "$output" == result=OK* ]]
  [ "$(field files "$output")" = 2 ]
  [ -f "$(field dir "$output")/README.md" ]
}

@test "the wrapper directory is stripped, so paths are repo-relative" {
  run "$FETCH" acme/repo abc123
  local dir; dir="$(field dir "$output")"
  [ -f "$dir/dnbg-workflow/skills/SKILL.md" ]
  [ ! -d "$dir/acme-repo-abc123" ]
}

# THE FAILURE THE SCRIPT EXISTS FOR. Without the empty check the caller gets a
# directory it can sweep, and the sweep comes back clean.
@test "a bad SHA reports the fetch failure rather than an empty tree" {
  echo bad > "$MODE"
  run "$FETCH" acme/repo deadbeef
  [ "$status" -eq 0 ]
  [ "$output" = "result=ERROR reason=fetch" ]
}

# The same hazard reached the other way: both sides of the pipe succeed and the
# tree is still empty, so exit codes alone would report OK.
@test "an archive that extracts nothing is an error, not a clean sweep" {
  echo hollow > "$MODE"
  run "$FETCH" acme/repo abc123
  [ "$output" = "result=ERROR reason=empty" ]
}

@test "an explicit target directory is used, and created if absent" {
  run "$FETCH" acme/repo abc123 "$BATS_TEST_TMPDIR/target/nested"
  [ "$(field dir "$output")" = "$BATS_TEST_TMPDIR/target/nested" ]
  [ -f "$BATS_TEST_TMPDIR/target/nested/README.md" ]
}

# Two SHAs blended into one directory would match neither, and every later read
# would be of a tree that never existed.
@test "a non-empty target directory is refused" {
  mkdir -p "$BATS_TEST_TMPDIR/used"; echo stale > "$BATS_TEST_TMPDIR/used/old"
  run "$FETCH" acme/repo abc123 "$BATS_TEST_TMPDIR/used"
  [ "$output" = "result=ERROR reason=bad-args" ]
  [ -f "$BATS_TEST_TMPDIR/used/old" ]
}

@test "a malformed repo is bad-args, not a fetch failure" {
  run "$FETCH" repo abc123
  [ "$output" = "result=ERROR reason=bad-args" ]
}

@test "missing arguments are bad-args" {
  run "$FETCH"
  [ "$output" = "result=ERROR reason=bad-args" ]
  run "$FETCH" acme/repo
  [ "$output" = "result=ERROR reason=bad-args" ]
}
