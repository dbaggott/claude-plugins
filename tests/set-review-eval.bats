#!/usr/bin/env bats
#
# Tests for the set-review eval's fixture filer. `gh` is stubbed: `issue create`
# answers the next URL in sequence and keeps the body it was given, and every
# call is logged, so the bodies and relationships the script files can be read
# back without touching GitHub.

bats_require_minimum_version 1.5.0

CREATE="${BATS_TEST_DIRNAME}/evals/set-review/create.sh"
U=https://github.com/o/r/issues

setup() {
  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  export LOG="$BATS_TEST_TMPDIR/log"; : > "$LOG"
  export BODIES="$BATS_TEST_TMPDIR/bodies"; mkdir -p "$BODIES"
  export FAIL_ON="${FAIL_ON:-}"
  cat > "$STUB/gh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "\$LOG"
[ -n "\$FAIL_ON" ] && [[ "\$*" == *"\$FAIL_ON"* ]] && exit 1
body=""; prev=""
for a in "\$@"; do [ "\$prev" = --body-file ] && body="\$a"; prev="\$a"; done
case "\$1 \$2" in
  "issue create")
    n=\$(( \$(ls "\$BODIES" | wc -l) + 1 ))
    cp "\$body" "\$BODIES/\$n"
    echo "Creating issue in o/r"; echo "$U/\$n" ;;
  "issue edit")
    [ -z "\$body" ] || cp "\$body" "\$BODIES/edited-\${3##*/}" ;;
esac
exit 0
EOF
  chmod +x "$STUB/gh"
  export PATH="$STUB:$PATH"
}
line() { tail -1 <<<"$1"; }

@test "files a parent and three children, then links them" {
  run "$CREATE" o/r
  [ "$status" -eq 0 ]
  [ "$(line "$output")" = "result=OK parent=$U/1 children=$U/2,$U/3,$U/4" ]
  [ "$(head -1 <<<"$output")" = "$U/1" ]
  grep -qx "issue edit $U/1 --repo o/r --add-sub-issue $U/2,$U/3,$U/4" "$LOG"
  grep -qx "issue edit $U/4 --repo o/r --add-blocked-by $U/2" "$LOG"
  # The planted dependency has no edge: the checker is never blocked by anything.
  run ! grep -q "edit $U/3 .*--add-blocked-by" "$LOG"
}

@test "every placeholder is filled, and the parent's table links the children" {
  run "$CREATE" o/r
  run ! grep -l '{{' "$BODIES"/*
  grep -qF "| [1]($U/2) | Export script | R0, R1 |" "$BODIES/edited-1"
  grep -qF "| [3]($U/4) | Import script | R3 | 1 |" "$BODIES/edited-1"
  grep -qF "Sub-issue of $U/1" "$BODIES/2"
  grep -qF "**Depends on:** $U/2" "$BODIES/4"
  grep -qF '**Depends on:** none' "$BODIES/3"
}

@test "the parent opens with the tracking-issue declaration" {
  run "$CREATE" o/r
  head -1 "$BODIES/edited-1" | grep -q '^This is a \*\*tracking issue\*\*'
}

@test "the planted coverage gap is present: R4 is in no Covers line and unmarked" {
  local fix="${BATS_TEST_DIRNAME}/evals/set-review/fixtures"
  grep -q '^- \*\*R4\.\*\*' "$fix/parent.md"
  run ! grep -E '^- \*\*R4\.\*\*.*\*\((end-to-end|deferred):' "$fix/parent.md"
  run ! grep -l R4 <(grep -h '^\*\*Covers:\*\*' "$fix"/child-*.md)
}

@test "a failed create stops before any linking" {
  FAIL_ON="issue create" run "$CREATE" o/r
  [ "$output" = "result=ERROR reason=create-failed" ]
  run ! grep -q '^issue edit' "$LOG"
}

@test "a failed link is reported with what was filed, not printed as a usable set" {
  FAIL_ON="--add-sub-issue" run "$CREATE" o/r
  [ "$output" = "result=ERROR reason=link-failed created=$U/1,$U/2,$U/3,$U/4" ]
}

@test "a create failing partway names the issues already filed" {
  FAIL_ON="Export checker" run "$CREATE" o/r
  [ "$output" = "result=ERROR reason=create-failed created=$U/1,$U/2" ]
}

@test "bad arguments are refused before any call" {
  local a
  for a in "or" "o/r/x" "/r" "o/"; do
    run "$CREATE" "$a"
    [ "$output" = "result=ERROR reason=bad-args" ] || { echo "accepted: $a"; false; }
  done
  run "$CREATE" o/r extra
  [ "$output" = "result=ERROR reason=bad-args" ]
  [ ! -s "$LOG" ]
}

@test "runs under the system bash" {
  [ -x /bin/bash ] || skip "no /bin/bash"
  run /bin/bash "$CREATE" o/r
  [ "$(line "$output")" = "result=OK parent=$U/1 children=$U/2,$U/3,$U/4" ]
}
