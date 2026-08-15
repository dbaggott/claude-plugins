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
#
# This test once also pinned the two skills' fenced copies of the comparison
# against each other. That half is gone with the copies: both now call
# `scripts/pr-verdict.sh`, and a single implementation cannot disagree with
# itself. `tests/pr-verdict.bats` covers what the pin could only approximate —
# that the check takes the last VERDICT rather than the last approval, which is
# the bug the pin was written for and which it could only detect as a missing
# grep hit.
@test "nothing reaches for branch protection to decide whether an approval counts" {
  # Any reintroduction is a regression regardless of intent: the endpoint needs
  # admin (403/404 on write-only access) and answers the wrong question. The
  # skills may still *name* the setting to explain why not to read it, so match
  # the call, not the words.
  #
  # `scripts/` is in scope alongside `skills/` now that the check lives there —
  # the wrong approach is reintroducible wherever the right one is implemented,
  # and scoping this to prose would leave the actual implementation unguarded.
  if grep -rn 'branches/[^ ]*/protection' \
       "$ROOT/dnbg-workflow/skills" "$ROOT/dnbg-workflow/scripts"; then
    echo "the admin-gated protection endpoint is called — use pr-verdict.sh instead"
    false
  fi
}

# The manifest and lib.sh both state a default for each mechanical knob, and they
# are read by different audiences at different times: the manifest's is what the
# configuration dialog pre-fills, lib.sh's is what an unconfigured session
# actually uses. Two statements of one value is a drift risk taken deliberately —
# the manifest cannot supply the running default (an option nobody configured
# exports nothing to a hook), and dropping it from the manifest would leave the
# dialog offering an empty box for a knob that has a documented default. So they
# are pinned together instead.
@test "the manifest's declared defaults match the ones lib.sh falls back to" {
  local manifest="$ROOT/dnbg-workflow/.claude-plugin/plugin.json"
  # shellcheck source=../dnbg-workflow/hooks/lib.sh
  . "$ROOT/dnbg-workflow/hooks/lib.sh"

  local from_manifest
  from_manifest=$(jq -r '.userConfig.worktree_path.default' "$manifest")
  [ "$from_manifest" = "$DEFAULT_WORKTREE_PATH" ] || {
    echo "worktree_path default disagrees: manifest '$from_manifest', lib.sh '$DEFAULT_WORKTREE_PATH'"
    false
  }

  from_manifest=$(jq -r '.userConfig.claim_label.default' "$manifest")
  [ "$from_manifest" = "$DEFAULT_CLAIM_LABEL" ] || {
    echo "claim_label default disagrees: manifest '$from_manifest', lib.sh '$DEFAULT_CLAIM_LABEL'"
    false
  }
}

# `version_stamp` is pinned separately rather than as a third arm above, because
# it has no lib.sh constant to compare against: it is a gate, and what an
# unconfigured session does is decided by how `version_stamp_enabled` reads an
# unset variable. A constant nothing consults would pin nothing.
#
# Its default is also the one here that is a safety property rather than a
# convenience — it puts text on PR descriptions, review bodies and issue comments
# that people who never installed this plugin will read. A dialog pre-ticked to
# on would opt every existing install in at the next update, which no amount of
# documentation undoes after the fact.
@test "the version stamp defaults to off on both sides" {
  local manifest="$ROOT/dnbg-workflow/.claude-plugin/plugin.json"
  # shellcheck source=../dnbg-workflow/hooks/lib.sh
  . "$ROOT/dnbg-workflow/hooks/lib.sh"

  [ "$(jq -r '.userConfig.version_stamp.default' "$manifest")" = "false" ] || {
    echo "the manifest offers the version stamp pre-enabled"
    false
  }
  # The resolver, not the constant: what an unconfigured session gets is decided
  # by how the resolver reads an unset variable, and a constant nothing consults
  # would pin nothing.
  ( unset CLAUDE_PLUGIN_OPTION_VERSION_STAMP; ! version_stamp_enabled ) || {
    echo "an unconfigured session stamps"
    false
  }
}

# The exclusion decision in reverse. "Configurable opinions with opinionated
# defaults" draws its line at mechanical-vs-behavioral, and the behavioral side —
# drafts always, the send-to-review picker and its fixed option order, the
# `[<branch-name>]` sibling title tag, "only a human merges" — is meant to have no
# key at all. Nothing else notices a fifth key appearing, so the surface is
# pinned by equality: a new knob is a decision to make deliberately, and this is
# the test that makes someone make it.
#
# `version_stamp` is the one key that is neither a mechanical name nor a
# workflow step, and it earns its place on a third ground: what it publishes is a
# marker addressed to *tooling*, meaningless to the humans it lands in front of.
# Nobody reading the PR can act on it, so it is theirs to decline. Content
# addressed to those readers is not covered — the `[<branch-name>]` title tag
# above writes onto a PR title people read, and stays an opinion because it is
# there to be read. "The operator might prefer otherwise" is not a ground either,
# or every behavioral choice above qualifies.
@test "the plugin exposes exactly the four intended configuration keys" {
  local keys
  keys=$(jq -r '.userConfig | keys_unsorted[]' "$ROOT/dnbg-workflow/.claude-plugin/plugin.json" | sort | tr '\n' ' ')
  [ "$keys" = "claim_label owners version_stamp worktree_path " ] || {
    echo "userConfig keys are: $keys"
    echo "adding one means deciding it is mechanical, or that it governs what gets published — see docs/configuration.md"
    false
  }
}

# "Which PRs belong to this issue?" is asked in three places, and each answer gates
# something different: whether the reviewer wakes, whether it discovers, and whether a
# coder believes the issue is unclaimed. They drifted — discovery grew the timeline
# source and the other two kept only `closedByPullRequestsReferences`, which lists PRs
# carrying a CLOSING KEYWORD and nothing else. Since `git-workflow` has exactly one
# sibling close an issue and the rest merely mention it, the narrow sources miss the
# shape that skill mandates: the reviewer's wait sat out its whole window on a real PR,
# and the claim check reads an in-flight multi-repo change as unclaimed.
#
# The failure is silent at every site — a wait that never fires and a claim check that
# finds nothing look exactly like a quiet issue — so prose could not hold it. This is
# the check.
#
# Two of the three sites now CALL `scripts/pr-sources.sh` rather than carrying their
# own copy, so for them the question is only whether they still invoke it. The third,
# `watch-pr.sh --issue`, keeps inline queries deliberately (see its own comments: it
# reads `.state` from the same `gh issue view`, and needs the timeline's fetch and
# parse failures counted separately with poll_broken's awake-time grace, neither of
# which survives a CLI boundary). So it is the one site that can still narrow alone —
# and it is now compared against the script rather than against prose, which is what
# `covers_discovery` could never do before: real code on both sides.

# Each extractor returns the API surfaces its site queries, one per line, under names
# shared across the three files so they can be compared as sets. Taking the file as an
# argument is what lets the induced-failure tests below run the real code against
# fixtures rather than only against the passing case.

# Only the lines a site actually runs — fenced-block contents for a skill, the whole
# file for a script, minus comments in both. A plain grep over the file counts a source
# NAMED in prose as a source QUERIED, and worse, counts the exemption marker's own text
# (which has to name the source it exempts) as coverage of it. Either way the check
# passes while the site stays blind, which is the single failure it exists to prevent.
pr_command_lines() {  # <file>
  case "$1" in
    # Indented fences count: a fence inside a numbered list item is still a
    # command block, and anchoring at column 0 would make every command in one
    # invisible to the checks below — a place to hide exactly what they look for.
    *.md) awk '/^[[:space:]]*```/ { inside = !inside; next } inside' "$1" ;;
    *)    cat "$1" ;;
  esac | grep -v '^[[:space:]]*#'
}

pr_sources() {  # <file>
  # `<n>` in a skill, `$PR` in the watcher, `$ISSUE` in pr-sources.sh: the same
  # endpoint spelled for three audiences, so all of them normalise to `timeline`.
  pr_command_lines "$1" \
    | grep -oE 'closedByPullRequestsReferences|issues/(<n>|\$PR|\$ISSUE)/timeline|gh search prs' \
    | sed 's|issues/.*/timeline|timeline|' | sort -u
}

# A site may decline a source, but only out loud. The marker carries the reason inline,
# so the exemption is a decision on the record rather than a gap that accumulated.
pr_exemptions() {  # <file>
  # `[a-z]+( [a-z]+)*` rather than `[a-z ]+`: the latter is greedy over the space too,
  # so it captures the one before the em-dash and every exemption arrives with trailing
  # whitespace that no exact-match comparison can ever satisfy.
  grep -oE 'PR-SOURCE-EXEMPT: [a-z]+( [a-z]+)*' "$1" | sed 's/PR-SOURCE-EXEMPT: //' | sort -u
}

# Every source discovery uses must be either polled by the site or exempted by it.
# Deliberately one-directional: a site querying something discovery does not is not a
# drift this test can judge, while a site quietly seeing LESS than discovery is exactly
# the bug above.
covers_discovery() {  # <site-file> <discovery-file>
  local want have exempt missing=""
  want=$(pr_sources "$2")
  have=$(pr_sources "$1")
  exempt=$(pr_exemptions "$1")

  [ -n "$want" ] || { echo "no PR sources found in the discovery file"; return 1; }

  local s
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    printf '%s\n' "$have"   | grep -qxF "$s" && continue
    printf '%s\n' "$exempt" | grep -qxF "$s" && continue
    missing="$missing $s"
  done <<EOF
$want
EOF

  [ -z "$missing" ] || {
    echo "$(basename "$1") is narrower than discovery — unhandled source(s):$missing"
    echo "  discovery: $(echo "$want" | tr '\n' ' ')"
    echo "  this site: $(echo "$have" | tr '\n' ' ')"
    echo "  exempted:  $(echo "$exempt" | tr '\n' ' ')"
    echo "poll the source, or declare 'PR-SOURCE-EXEMPT: <source> — <reason>' at the site"
    return 1
  }
}

# The canonical union, and now the thing every other site is measured against.
# Deliberately the script and not `reviewer`'s prose: the old reference could only
# ever prove a site NAMED the same endpoints, never that it queried them the same
# way, and `covers_discovery`'s own extractor exists because a prose mention had to
# be told apart from a query.
DISCOVERY="$ROOT/dnbg-workflow/scripts/pr-sources.sh"

@test "the issue-scoped wait sees every PR source discovery does" {
  run covers_discovery "$ROOT/dnbg-workflow/scripts/watch-pr.sh" "$DISCOVERY"
  echo "$output"
  [ "$status" -eq 0 ]
}

# The two prose sites can no longer narrow by rewriting a query, because they have
# no query — so what is left to protect is that they still call the union rather
# than growing a private one back. A site that reintroduced its own copy would fail
# this by dropping the invocation, which is the reachable regression; one that kept
# BOTH would be caught by review, not by a grep.
@test "the prose discovery sites call the union rather than carrying a copy" {
  local f
  for f in "$ROOT/dnbg-workflow/skills/issue-workflow/references/resolving.md" \
           "$ROOT/dnbg-workflow/skills/reviewer/references/issue-mode.md"; do
    grep -q 'pr-sources\.sh' "$f" || {
      echo "$(basename "$f") no longer invokes pr-sources.sh"; false; }
    # And it must be an invocation, not a mention: the same distinction
    # `pr_command_lines` draws, applied to the call itself.
    pr_command_lines "$f" | grep -q 'pr-sources\.sh' || {
      echo "$(basename "$f") names pr-sources.sh in prose but never runs it"; false; }
  done
}

# A site file in the shape the extractor expects: commands inside a fence, everything
# else prose. Shaped as `.md` because that is the harder case — a script has no prose
# for a mention to hide in.
fixture_site() {  # <fenced-body>
  cat > "$BATS_TEST_TMPDIR/site.md" <<EOF
Prose above the block, mentioning gh search prs and closedByPullRequestsReferences
in passing — neither is a query, and neither may count as one.

\`\`\`bash
$1
\`\`\`

Prose below, same rule.
EOF
  echo "$BATS_TEST_TMPDIR/site.md"
}

@test "a site polling only the closing-keyword source is caught" {
  # The exact regression, induced: the shape both sites had before, which no test
  # could distinguish from a quiet issue.
  run covers_discovery \
    "$(fixture_site 'gh issue view <n> --json closedByPullRequestsReferences')" \
    "$DISCOVERY"
  [ "$status" -ne 0 ]
  [[ "$output" == *"narrower than discovery"* ]]
  [[ "$output" == *"timeline"* ]]
}

@test "a source only NAMED in prose does not count as one queried" {
  # The fixture's prose names every source; the block queries two. Were mentions
  # counted, this would pass while the site never runs the third — and the same
  # accident would let the exemption marker vouch for the source it exempts.
  run covers_discovery "$(fixture_site 'gh issue view <n> --json closedByPullRequestsReferences
gh api repos/x/issues/<n>/timeline --paginate')" "$DISCOVERY"
  [ "$status" -ne 0 ]
  [[ "$output" == *"gh search prs"* ]]
}

@test "a marked exemption does count, so a fourth source is a decision not a silence" {
  run covers_discovery "$(fixture_site 'gh issue view <n> --json closedByPullRequestsReferences
gh api repos/x/issues/<n>/timeline --paginate
# PR-SOURCE-EXEMPT: gh search prs — rate-limited well below core REST.')" \
    "$DISCOVERY"
  echo "$output"
  [ "$status" -eq 0 ]
}

# What counts as a verdict is asked in two places that cannot share a query: `pr-verdict.sh`
# fetches its own payload, while `watch-pr.sh`'s level-triggered check reads the `reviews`
# already in the poll it just made — a CLI boundary there would double the request rate of
# every tick. So the SET is what has to stay pinned, and it is exactly the kind that drifts
# quietly: adding a state to one side leaves the watch waking on something the author's
# ready-to-merge check does not treat as a verdict, or missing one it does.
#
# Same extraction rule as above — run lines only, no comments. Both files have to NAME the
# excluded states to explain themselves, and a grep over whole files would read those
# explanations as agreement no matter what the queries did.
verdict_states() {  # <file>
  pr_command_lines "$1" \
    | grep -oE 'APPROVED|CHANGES_REQUESTED|DISMISSED|COMMENTED' | sort -u
}

@test "the watcher and pr-verdict.sh agree on what a verdict is" {
  local a b
  a=$(verdict_states "$ROOT/dnbg-workflow/scripts/pr-verdict.sh")
  b=$(verdict_states "$ROOT/dnbg-workflow/scripts/watch-pr.sh")
  echo "pr-verdict.sh: $(echo "$a" | tr '\n' ' ')"
  echo "watch-pr.sh:   $(echo "$b" | tr '\n' ' ')"
  [ -n "$a" ]
  [ "$a" = "$b" ]
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
  # RUNNING one is what makes a suite a watch-spawning suite.
  #
  # Comment lines are excluded, and that is the selection rather than tidying. A grep
  # over whole files reads a suite that merely MENTIONS a watcher — "the gate
  # watch-pr.sh applies to .state", explaining where a rule came from — as one that
  # spawns it, and then fails it for not loading two helpers it has no use for. The
  # diagnosis is true of the text and useless about the suite, and the pressure it
  # creates is to delete the explanation. Same distinction `pr_command_lines` draws
  # above, for the same reason.
  for f in "$ROOT"/tests/*.bats; do
    grep -v '^[[:space:]]*#' "$f" \
      | grep -q 'watch-pr\.sh\|watch-merge\.sh\|lib-poll\.sh' || continue
    # ⚠️ SKIP SELF. This file has to name the watcher scripts to select on them, and
    # the pattern above sits on a line the exclusion does not reach — so without this
    # coupling.bats selects itself and fails with "coupling.bats spawns a watch but
    # never loads reap": true of the text, useless as a diagnosis.
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

# The README's skill table is a *promise per skill*, and its second and
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
      echo "$skill is not repo-scoped but reads the origin remote — see docs/forge-support.md 'What happens on an unsupported forge'"
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

# The decline table drifted from the skill it describes, one round after
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
  offenders=$(awk '/^## What happens on an unsupported forge$/{inside=1; next} inside && /^##/{exit} inside' \
      "$ROOT/docs/forge-support.md" \
    | grep -E '^\| `[a-z-]+` \|' \
    | grep -iE '\|[[:space:]]*(same|as above|ditto|likewise)[[:space:]]*\|' || true)
  if [ -n "$offenders" ]; then
    echo "$offenders"
    echo "a decline-table row inherits its rule from a neighbour — spell it out, or it cannot go visibly stale"
    false
  fi
}

# Every file under `reviewer/references/` is reachable only through the pointer
# SKILL.md carries for it — nothing else in the plugin names one, and the discovery
# check above reads issue-mode.md directly, so dropping a pointer leaves that file
# unreachable with the whole suite green. That is the silent direction, and this is
# the check for it. It matters most for the files the reviewer needs *mid-cycle*:
# an agent that never loads watch.md branches on `result=` from the names alone.
#
# Deliberately a bare filename grep: what must not vanish is the *name*, since an
# agent reading SKILL.md can only find the file by seeing it mentioned. Asserting
# the wording of the surrounding paragraph would fail on every edit that keeps the
# pointer working, which is how a check gets deleted rather than fixed.
#
# Globbed rather than enumerated so a reference file added later is covered without
# anyone remembering to come back here.
@test "SKILL.md points at every one of its reference files" {
  local s skill f bad=0
  # Every skill with a references/ directory, so a new one is covered by adding its
  # name rather than by copying the loop.
  for s in reviewer git-workflow; do
    local found=0
    skill="$ROOT/dnbg-workflow/skills/$s/SKILL.md"
    # `nullglob` so an emptied references/ yields no iterations rather than one over
    # the literal pattern — without it the count below can never reach zero, and the
    # emptied case reports a missing pointer to a file named `*.md`.
    shopt -s nullglob
    for f in "$ROOT/dnbg-workflow/skills/$s/references/"*.md; do
      found=$((found + 1))
      grep -q "$(basename "$f" | sed 's/\./\\./g')" "$skill" || {
        echo "$s/SKILL.md no longer names $(basename "$f") — nothing can reach it"
        bad=1
      }
    done
    shopt -u nullglob
    # Zero files is the one way this check goes quiet: every assertion is in the loop.
    [ "$found" -gt 0 ] || { echo "$s/references/ has no .md files at all"; bad=1; }
  done
  [ "$bad" -eq 0 ]
}

# A `description:` whose value contains an unquoted `: ` is not a description with
# a colon in it — YAML reads the colon as a mapping indicator, the frontmatter
# stops parsing, and Claude Code loads the skill with EVERY field dropped. The
# skill then has no name and no description, so nothing can route to it. Silent at
# runtime, and invisible to the rest of this suite, which never parses a SKILL.md.
#
# `claude plugin validate --strict` in CI is the authority and catches more than
# this. It needs the CLI installed, which the bats job does not have — so this is
# the narrow local check for the one failure mode that has actually happened,
# not a second parser.
@test "every skill description survives YAML plain-scalar parsing" {
  local f skill plugin bad=0
  while read -r skill plugin; do
    f="$ROOT/$plugin/skills/$skill/SKILL.md"
    grep -q '^name:' "$f" || { echo "$skill/SKILL.md has no name: in its frontmatter"; bad=1; }
    local v
    v=$(sed -n 's/^description: //p' "$f")
    [ -n "$v" ] || { echo "$skill/SKILL.md has no description:"; bad=1; continue; }
    # Quoted scalars may contain anything; only a plain one is at risk.
    case "$v" in
      \"*|\'*) ;;
      *": "*)
        echo "$skill: description contains an unquoted ': ' — YAML will drop the whole frontmatter"
        echo "  use an em dash, or quote the value"
        bad=1 ;;
    esac
  done < <(tree_skills)
  [ "$bad" -eq 0 ]
}

# `issue-workflow`'s two halves are reachable only through the pointers SKILL.md
# carries — nothing else in the plugin names either file, and the claim check above
# reads resolving.md directly, so dropping a pointer would strand a whole path with
# the suite green. Same silent direction the reviewer pointer test covers.
@test "issue-workflow SKILL.md still points at both halves" {
  local skill="$ROOT/dnbg-workflow/skills/issue-workflow/SKILL.md" f
  for f in creating resolving; do
    [ -f "$ROOT/dnbg-workflow/skills/issue-workflow/references/$f.md" ] || {
      echo "references/$f.md is missing"; false; }
    grep -q "references/$f\.md" "$skill" || {
      echo "issue-workflow/SKILL.md no longer names references/$f.md — that path is unreachable"
      false; }
  done
}

# `verdict=` is now answered in three places — pr-verdict.sh, watch-pr.sh's
# level-triggered check, and the round packet — but only the first two can hold a
# copy of the RULE. The packet delegates, so the set stays pinned by the test
# above rather than needing a third arm that would have to be kept in step.
@test "pr-round.sh delegates the verdict rather than carrying a third copy" {
  local f="$ROOT/dnbg-workflow/scripts/pr-round.sh"
  local states
  states=$(verdict_states "$f")
  [ -z "$states" ] || {
    echo "pr-round.sh names verdict states itself: $(echo "$states" | tr '\n' ' ')"
    echo "call pr-verdict.sh instead — tests/coupling.bats pins the set across two files, not three"
    false
  }
  pr_command_lines "$f" | grep -q 'pr-verdict\.sh' || {
    echo "pr-round.sh no longer invokes pr-verdict.sh, so its verdict comes from nowhere"; false; }
  pr_command_lines "$f" | grep -q 'pr-threads\.sh' || {
    echo "pr-round.sh no longer invokes pr-threads.sh"; false; }
}

# The watcher emits the activity it already polled and the packet fetches the
# same thing; a caller reads both, so the objects have to match field for field.
# One sourced definition is what makes that true — spelling the filter inline in
# either file is the drift, and it is silent (the two just disagree).
#
# The selection predicate is pinned, not only the object shape, AND IT IS THE HALF
# THAT COSTS DATA. `watch-pr.sh` counts what it emits in order to set `activity=1`;
# a count filtered differently from the emission prints `activity=1` above an EMPTY
# payload, which a caller now told the payload is the conversation reads as nothing
# landed — and it then re-arms with `since_iso` set to now, losing it permanently.
# Deriving both counts from the shared filters is what makes that unreachable, so a
# reintroduced inline `select(...)` on those fields is the regression to catch.
@test "both activity producers source the shared filters instead of spelling them" {
  local f runlines
  for f in "$ROOT/dnbg-workflow/scripts/watch-pr.sh" \
           "$ROOT/dnbg-workflow/scripts/pr-round.sh"; do
    grep -q 'lib-activity\.sh' "$f" || {
      echo "$(basename "$f") no longer sources lib-activity.sh"; false; }
    # Run lines only: both files have to NAME these fields in prose to explain
    # themselves, and a whole-file grep would read the explanation as the offence.
    runlines=$(grep -v '^[[:space:]]*#' "$f" || true)
    printf '%s\n' "$runlines" | grep -q 'kind: *"' && {
      echo "$(basename "$f") spells an activity object inline — use lib-activity.sh"; false; }
    printf '%s\n' "$runlines" | grep -qE 'select\(\.(submittedAt|createdAt|created_at)' && {
      echo "$(basename "$f") spells an activity predicate inline — use lib-activity.sh"
      echo "a count filtered differently from the emission prints activity=1 over an empty payload"
      false; }
  done
  # And the shared file really does define both, or the greps above pass on a
  # source that supplies nothing.
  local lib="$ROOT/dnbg-workflow/scripts/lib-activity.sh"
  grep -q '^ACTIVITY_JQ_REVIEWS=' "$lib"
  grep -q '^ACTIVITY_JQ_INLINE=' "$lib"
  # The summary is a projection of those two, not a third description of the
  # shape. Spelled anywhere else it drifts from what it claims to be a subset of.
  grep -q '^ACTIVITY_JQ_SUMMARY=' "$lib"
  grep -q 'ACTIVITY_JQ_SUMMARY' "$ROOT/dnbg-workflow/scripts/watch-pr.sh"
}

# The whole-tree fetch is a script for one reason: a failed fetch leaves an EMPTY
# tree, and the caller's next move is usually a repo-wide sweep, where zero hits
# reads as "nothing references it" rather than "nothing was fetched". A fenced
# `gh api .../tarball/... | tar xz` in the prose reports neither failure — a bad
# SHA only fails the pipeline, which nothing downstream reads, and an archive with
# no members lets both sides exit 0 — so re-inlining it silently restores the
# hazard. Catch the re-inlining, not the mention: the prose may describe what the
# script does.
@test "the tree fetch calls fetch-tree.sh rather than piping a tarball inline" {
  local f bad=0
  while IFS= read -r f; do
    pr_command_lines "$f" | grep -qE '/tarball/' && {
      echo "${f#"$ROOT"/} pipes a tarball inline — call fetch-tree.sh, which fails on an empty tree"
      bad=1; }
  done < <(find "$ROOT" -path "$ROOT/.git" -prune -o -name '*.md' -path '*/skills/*' -print)
  [ "$bad" -eq 0 ]

  # The other direction: deleting the call would pass the check above trivially.
  local skill="$ROOT/dnbg-workflow/skills/reviewer/SKILL.md"
  pr_command_lines "$skill" | grep -q 'fetch-tree\.sh' || {
    echo "reviewer/SKILL.md names no tree fetch — the third access mode is unreachable"; false; }
}
