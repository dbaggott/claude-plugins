#!/usr/bin/env bats
#
# The tool list that check-worktree.sh gates lives in three places, and its own
# comment says a tool missing from any of them is editable in the main checkout
# without the gate firing. That is a silent, security-relevant failure with no
# other check on it — this is the check.

ROOT="${BATS_TEST_DIRNAME}/.."

# The heading of the always-on rule that states the gate. The tool enumeration is
# read from this section alone, so a slash-run anywhere else in the file — a
# future rule mentioning GitHub/GitLab, say — can never be read as a tool list.
GATE_SECTION='All file changes in a covered repo go through a PR'

# The three extractors. Each takes its file as an argument rather than reading a
# fixed path, so the same code that checks the real files is what the induced
# failures below run against — a check that can only be pointed at the passing
# case is a check nobody has seen fail.

# check-worktree.sh's `case` — the set the script itself acts on.
case_tools() {  # <check-worktree.sh>
  sed -n 's/^  \(\([A-Za-z]*|\)*[A-Za-z]*\)) ;;$/\1/p' "$1" | tr '|' '\n' | sort -u
}

# hooks.json — the set Claude Code actually invokes the hook for. A tool here but
# not in the case is a wasted invocation; a tool in the case but not here never
# reaches the script at all.
matcher_tools() {  # <hooks.json>
  jq -r '.hooks.PreToolUse[] | select(.hooks[].command | test("check-worktree")) | .matcher' "$1" \
    | tr '|' '\n' | sort -u
}

# always-on-rules.md — what the agent reads. It is prose, so the enumeration is
# taken from the one construct in the gate section that enumerates: the
# slash-delimited run of capitalised names ("Edit/Write/NotebookEdit"). That run
# is the convention, and it costs the rules file nothing — the prose already
# wrote the list that way. A tool claimed gated in free prose *outside* the run
# is not seen here; the run is the enumeration.
rules_tools() {  # <always-on-rules.md>
  # awk rather than a sed range: a `/^## x/,/^## /` range ends *inclusive* of the
  # next heading, so a future heading that itself carried a slash-run would be
  # read as part of the gate enumeration. This stops before it.
  awk -v h="## $GATE_SECTION" '$0 == h { inside = 1; next } /^## / { inside = 0 } inside' "$1" \
    | grep -oE '[A-Z][A-Za-z]+(/[A-Z][A-Za-z]+)+' | tr '/' '\n' | sort -u
}

# Set equality in both directions, which is the whole point: containment in the
# case→rules direction alone misses the case check-worktree.sh:15-18 actually
# warns about — a tool the rules tell the agent is gated while neither the case
# nor the matcher gates it. Equality also makes the substring accident
# structurally impossible, where a per-tool `grep` for `Edit` matched inside
# `NotebookEdit` and passed on a rules file that never named `Edit`.
gate_agrees() {  # <always-on-rules.md> <check-worktree.sh> <hooks.json>
  local from_rules from_case from_matcher
  from_rules=$(rules_tools "$1")
  from_case=$(case_tools "$2")
  from_matcher=$(matcher_tools "$3")

  [ -n "$from_case" ] || { echo "no gated tools found in the case"; return 1; }
  [ "$from_case" = "$from_matcher" ] || {
    echo "the case and the hooks.json matcher disagree:"
    echo "  case:    $(echo "$from_case" | tr '\n' ' ')"
    echo "  matcher: $(echo "$from_matcher" | tr '\n' ' ')"
    return 1
  }
  [ "$from_case" = "$from_rules" ] || {
    echo "the case and always-on-rules.md disagree:"
    echo "  case:  $(echo "$from_case" | tr '\n' ' ')"
    echo "  rules: $(echo "$from_rules" | tr '\n' ' ')"
    echo "the rules must name the gated tools as one slash-delimited run"
    echo "(Edit/Write/NotebookEdit) under '## $GATE_SECTION'"
    return 1
  }
}

# A rules file in the shape the extractor expects, with the tool run substituted.
# The decoy run in the first section is load-bearing, but only through the
# positive test below: the two negative tests assert a mismatch, and a decoy
# leaking in through an unscoped extractor only deepens a mismatch they were
# going to see anyway. It takes a fixture that is supposed to *agree* for the
# stray tools to break something.
fixture_rules() {  # <slash-delimited tool run>
  cat > "$BATS_TEST_TMPDIR/rules.md" <<EOF
## No flattery

Not the gate section, and it names Read/Glob to prove the scan ignores it.

## $GATE_SECTION

Any edit to a tracked file goes through a worktree + draft PR. Load the
\`dnbg-workflow:git-workflow\` skill before the first
$1 call so the worktree/PR flow is in context.

## Reference issues and PRs by full URL

Nothing to enumerate here either.
EOF
  echo "$BATS_TEST_TMPDIR/rules.md"
}

@test "the gated tool list agrees across the case, the matcher, and the rules" {
  run gate_agrees "$ROOT/dnbg-workflow/always-on-rules.md" \
    "$ROOT/dnbg-workflow/hooks/check-worktree.sh" \
    "$ROOT/dnbg-workflow/hooks/hooks.json"
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "a rules file naming exactly the gated set agrees, decoys and all" {
  # The only one of these fixtures that is supposed to pass, and so the only one
  # that pins the section scoping: drop the scoping and the decoy `Read/Glob` in
  # the fixture's first section joins the enumeration, which makes this fail.
  # It is also the only direction that catches rules_tools returning too little.
  run gate_agrees "$(fixture_rules 'Edit/Write/NotebookEdit')" \
    "$ROOT/dnbg-workflow/hooks/check-worktree.sh" \
    "$ROOT/dnbg-workflow/hooks/hooks.json"
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "a rules file naming NotebookEdit but not Edit is caught" {
  # The substring accident, induced rather than asserted against the pattern:
  # `Edit` occurs inside `NotebookEdit`, so the old per-tool containment check
  # passed on exactly this file.
  run gate_agrees "$(fixture_rules 'Write/NotebookEdit')" \
    "$ROOT/dnbg-workflow/hooks/check-worktree.sh" \
    "$ROOT/dnbg-workflow/hooks/hooks.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"always-on-rules.md disagree"* ]]
}

@test "a rules file naming a tool that is gated nowhere is caught" {
  # The reverse direction, which the one-directional check missed entirely: the
  # rules tell the agent Read is gated, the case and the matcher never gate it,
  # and the agent believes a protection it does not have.
  run gate_agrees "$(fixture_rules 'Edit/Write/NotebookEdit/Read')" \
    "$ROOT/dnbg-workflow/hooks/check-worktree.sh" \
    "$ROOT/dnbg-workflow/hooks/hooks.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"always-on-rules.md disagree"* ]]
}

# The "is HEAD approved?" question has exactly one correct source: an APPROVED
# review's commit oid compared to headRefOid. It was answered from
# `dismiss_stale_reviews` instead, in two skills independently, and that field is
# meaningless on a repo with `required_approving_review_count: 0` — which both
# repos these skills run against are. The wrong answer merged two PRs over
# unreviewed diffs. Prose alone did not hold the line, so this pins it.
@test "no skill reaches for branch protection to decide whether an approval counts" {
  # The endpoint itself. Any reintroduction is a regression regardless of intent:
  # it needs admin (403/404 on write-only access) and answers the wrong question.
  # Both skills may still *name* the setting to explain why not to read it, so
  # match the call, not the words.
  if grep -rn 'branches/[^ ]*/protection' "$ROOT/dnbg-workflow/skills"; then
    echo "a skill calls the admin-gated protection endpoint — use the commit-oid comparison instead"
    false
  fi

  # And the comparison is present in both skills, so removing it can't pass by
  # simply deleting the rule along with the endpoint.
  #
  # CHANGES_REQUESTED is pinned alongside APPROVED because the first cut of this
  # check took the last *approval* rather than the last *verdict*, so an approval
  # reversed at the same SHA still read as approved. The verdict set is the fix,
  # and it is the part a later simplification would quietly drop.
  for skill in reviewer git-workflow; do
    f="$ROOT/dnbg-workflow/skills/$skill/SKILL.md"
    grep -q 'headRefOid' "$f" || { echo "$skill/SKILL.md never mentions headRefOid"; false; }
    grep -q 'state=="APPROVED"' "$f" || { echo "$skill/SKILL.md has no APPROVED commit-oid check"; false; }
    grep -q 'state=="CHANGES_REQUESTED"' "$f" || {
      echo "$skill/SKILL.md checks the last approval, not the last verdict"; false; }
  done
}

# Two conventions that a suite opts into by `load`ing a file, and whose absence is
# invisible from inside the suite that forgot: a watch spawned without `trace-dir`
# files its trace in the DEVELOPER'S real directory, and one spawned without `reap`
# is stopped by nothing if an assertion fails before its kill. Both failures are
# silent and land outside the run, which is exactly the shape tests/reap.bash argues
# cannot be left to convention — "the next spawn in the suite without it inherits the
# belief and not the protection".
@test "every suite that spawns a watch loads the reaper and contains its traces" {
  local f missing=0
  # The watcher scripts and the library are the only things that start a watch, so
  # naming one is what makes a suite a watch-spawning suite.
  for f in $(grep -rl 'watch-pr\.sh\|watch-merge\.sh\|lib-poll\.sh' "$ROOT"/tests/*.bats); do
    # ⚠️ SKIP SELF. This file has to name the watcher scripts to select on them, so the
    # selection is one prose mention away from including this file — which spawns no
    # watch and loads neither helper, so it would fail with "coupling.bats spawns a
    # watch but never loads reap": true of the text, useless as a diagnosis. Today the
    # only mention is the pattern above, which happens not to match itself; that is a
    # coincidence of spelling, not a property worth relying on.
    if [ "$(basename "$f")" = "$(basename "$BATS_TEST_FILENAME")" ]; then continue; fi
    grep -q '^load reap$' "$f" || {
      echo "$(basename "$f") spawns a watch but never loads reap"; missing=1; }
    grep -q '^load trace-dir$' "$f" || {
      echo "$(basename "$f") spawns a watch but never loads trace-dir"; missing=1; }
    # `load`ing it is not the same as calling it, and only the call sets TMPDIR.
    grep -q 'contain_traces' "$f" || {
      echo "$(basename "$f") loads trace-dir but never calls contain_traces"; missing=1; }
  done
  [ "$missing" -eq 0 ]
}

# The README's forge support matrix is a *promise per skill*, and its second and
# third columns are only true if every skill the repo ships has actually been
# classified. A skill added without a row inherits neither claim, and the matrix
# keeps asserting complete coverage it no longer has — the rot this pins against.
#
# The "What's in it" table is the single classification (plugin + forge); the
# matrix section points at it rather than repeating the lists, so there is one
# place to update and this check has one place to read.
readme_skill_rows() {  # <README.md> -> "<skill> <plugin> <forge>"
  # Rows of the four-column table, keyed on the leading `| \`skill\` |`. The
  # forge cell is normalised to coupled/neutral: it is prose ("GitHub only",
  # "**Any**") so that a reader gets a sentence, and matching on "any" rather
  # than the exact spelling keeps the emphasis markup free to change.
  #
  # Scoped to the table, and every cell capture excludes `|`. The second is the
  # subtle one: with a greedy `\(.*\)` for the forge cell, a row whose
  # description contained a pipe would fold the Forge cell into the description
  # and read as `coupled`. The table-diff check below compares only the skill
  # and plugin columns, so a neutral skill would be misclassified in silence —
  # the exact drift these checks exist to catch.
  #
  # `What.s` rather than the apostrophe: the heading is matched inside a
  # single-quoted awk program, where a literal `'` cannot appear.
  awk '/^## What.s in it$/{inside=1; next} inside && /^## /{exit} inside' "$1" \
    | sed -n 's/^| `\([a-z-]*\)` | `\([a-z-]*\)` | \([^|]*\) | [^|]* |$/\1 \2 \3/p' \
    | while read -r skill plugin forge; do
        case "$(printf '%s' "$forge" | tr -d '*' | tr '[:upper:]' '[:lower:]')" in
          any) printf '%s %s neutral\n' "$skill" "$plugin" ;;
          *)   printf '%s %s coupled\n' "$skill" "$plugin" ;;
        esac
      done
}

tree_skills() {  # -> "<skill> <plugin>"
  local d
  for d in "$ROOT"/dnbg-*/skills/*/; do
    [ -f "$d/SKILL.md" ] || continue
    printf '%s %s\n' "$(basename "$d")" "$(basename "$(dirname "$(dirname "$d")")")"
  done | sort
}

@test "every skill in the tree is classified in the README, under the plugin that ships it" {
  # Both directions. A missing row is the rot above; a stale row is a matrix
  # promising a skill that no longer exists, or naming the wrong plugin — which
  # is the specific claim `velocity-tradeoff` exists to keep honest, since its
  # value is precisely that a neutral skill sits in the coupled plugin.
  run diff <(tree_skills) <(readme_skill_rows "$ROOT/README.md" | cut -d' ' -f1,2 | sort)
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "the README classifies velocity-tradeoff as neutral inside the coupled plugin" {
  # Pinned by name rather than left to the table check above, because this exact
  # pairing is the trap: it is the only neutral skill in `dnbg-workflow`, and a
  # future edit that "tidies" the table by making the plugin's rows uniform would
  # satisfy every other check here while inverting the promise.
  run readme_skill_rows "$ROOT/README.md"
  echo "$output"
  [[ "$output" == *"velocity-tradeoff dnbg-workflow neutral"* ]]
}

# Degradation is decided per skill, and for three of the coupled skills the
# working directory is the wrong input entirely: `reviewer` judges the repo
# holding the PR it was given, and `reviewer-setup` and `work-summary` touch no
# repo at all. A cwd check in any of them refuses a flow that works — a recap of
# your GitHub week asked from a GitLab checkout. The forge-neutral pair must not
# read a remote for the same reason, one step further out.
#
# This is the shape a later consistency pass reintroduces ("all the GitHub skills
# should check the host"), so the rule is pinned rather than merely written down.
#
# Match the *call*, not the words — the same distinction the protection-endpoint
# check above draws, and for the same reason. Three of these skills name the
# command in prose precisely to say they do not run it, and a bare substring
# match reads that disclaimer as the violation it warns against. A call is the
# command at the start of a line (a fenced code block) or inside a substitution;
# an inline mention is backtick-wrapped mid-sentence. That leaves an unusual
# spelling — a call piped into on one line, say — invisible here, which is the
# accepted cost of not failing on the disclaimers.
remote_read_calls() {  # <SKILL.md>
  grep -nE '^[[:space:]]*git remote get-url|\$\([[:space:]]*git remote get-url' "$1"
}

@test "only the repo-scoped skills read the remote to decide whether to run" {
  local f skill plugin bad=0
  while read -r skill plugin; do
    case "$skill" in git-workflow|issue-workflow) continue ;; esac
    f="$ROOT/$plugin/skills/$skill/SKILL.md"
    if remote_read_calls "$f"; then
      echo "$skill is not repo-scoped but reads the origin remote — see README 'What happens on an unsupported forge'"
      bad=1
    fi
  done < <(tree_skills)
  [ "$bad" -eq 0 ]
}

@test "the two repo-scoped skills do read the remote, and say what a non-GitHub host means" {
  # The other direction: deleting the check would pass the test above trivially.
  local skill f
  for skill in git-workflow issue-workflow; do
    f="$ROOT/dnbg-workflow/skills/$skill/SKILL.md"
    # The same call-not-words matcher, so "it reads the remote" means an actual
    # runnable line and not a sentence mentioning one.
    remote_read_calls "$f" >/dev/null || {
      echo "$skill/SKILL.md never reads the origin remote, so it cannot detect the host"; false; }
    grep -qi 'github-only' "$f" || {
      echo "$skill/SKILL.md reads the host but never states the flow is GitHub-only"; false; }
    # No `origin` is explicitly not a decline. Without this the safest-looking
    # reading of "not github.com" — treat unknown as unsupported — silently
    # breaks every local-only repo, which has no forge claim either way.
    grep -q 'No `origin`\|no `origin`' "$f" || {
      echo "$skill/SKILL.md does not say what to do in a repo with no origin"; false; }
  done
}

# `issue-workflow` is repo-scoped, but the repo is the one the ISSUE lives in —
# which the working directory only reveals when the issue is named by a bare
# number. The always-on rule requires full URLs, so the URL case is the common
# path, and resolving it from cwd breaks it in both directions: a GitHub issue
# URL declines from a GitLab checkout, and a GitLab issue URL proceeds from a
# GitHub one into the `gh issue view` cascade the section exists to prevent.
#
# Structural rather than keyword-matched, because "reads the remote" is true of
# the fixed file too — the fallback is still there. What must hold is the
# precedence: the URL rule is stated BEFORE the command, so the command reads as
# the fallback rather than as the rule.
@test "issue-workflow resolves the host from the issue URL, and the remote only as a fallback" {
  local f url_rule remote_line
  f="$ROOT/dnbg-workflow/skills/issue-workflow/SKILL.md"

  url_rule=$(grep -niE 'the host is in the URL' "$f" | head -1 | cut -d: -f1)
  [ -n "$url_rule" ] || {
    echo "issue-workflow never says the host comes from the issue URL"; false; }

  remote_line=$(remote_read_calls "$f" | head -1 | cut -d: -f1)
  [ -n "$remote_line" ] || {
    echo "issue-workflow has no remote read at all, so a bare issue number cannot be resolved"; false; }

  [ "$url_rule" -lt "$remote_line" ] || {
    echo "issue-workflow reads the remote before establishing that the URL decides the host"; false; }

  # And the command is framed as the fallback, not merely placed after the rule.
  grep -qi 'fall back' "$f" || {
    echo "issue-workflow's remote read is not framed as a fallback"; false; }
}

# The README's decline table drifted from the skill it describes, one round after
# the skill was corrected — `issue-workflow`'s rule cell read `same`, inheriting
# `git-workflow`'s origin rule, so when issue-workflow stopped deciding that way
# the cell could not go visibly stale: it still pointed at a neighbour whose rule
# was still right *for the neighbour*.
#
# This bans the inheriting placeholder, nothing more. It cannot tell whether a
# spelled-out rule is correct — checking prose against behavior would mean
# parsing one into the other, which is a worse trade than the drift it prevents.
# What it does buy is that a rule change has to touch the cell that states it,
# which is the step that was skipped. Keeping the artifacts honest past that
# stays a manual step, deliberately.
@test "every row of the decline table states its own rule instead of inheriting one" {
  local offenders
  # `|| true` because finding nothing is the passing case, and bats runs with
  # errexit — without it a clean table fails the assignment rather than the test.
  offenders=$(awk '/^### What happens on an unsupported forge$/{inside=1; next} inside && /^##/{exit} inside' \
      "$ROOT/README.md" \
    | grep -E '^\| `[a-z-]+` \|' \
    | grep -iE '\|[[:space:]]*(same|as above|ditto|likewise)[[:space:]]*\|' || true)
  if [ -n "$offenders" ]; then
    echo "$offenders"
    echo "a decline-table row inherits its rule from a neighbour — spell it out, or it cannot go visibly stale"
    false
  fi
}
