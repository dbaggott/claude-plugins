#!/usr/bin/env bash
# The always-on rules, plus any configuration overrides in force. Executed, not
# sourced, by both hooks that inject context: `inject-rules.sh` on SessionStart
# and `inject-rules-subagent.sh` on SubagentStart.
#
# It lives in its own file because those two hooks must emit the *same* rules. A
# subagent told a different set of rules than its parent is the failure this
# split exists to make impossible — not a coupling test that notices the drift
# afterwards, but one payload with one author.
#
# Keep always-on-rules.md small: every byte here costs tokens on every session
# *and* on every subagent spawn. Most guidance belongs in a skill (loaded on
# demand) instead.

set -u
# shellcheck source=./lib.sh
. "$(dirname "$0")/lib.sh"

# `${CLAUDE_PLUGIN_ROOT:-}` (not bare) keeps `set -u` from aborting if Claude
# Code ever invokes the hook without setting the var. The file-existence guard
# below then silently no-ops on the resulting `/always-on-rules.md` path,
# matching the broken-install behavior the comment promises.
RULES="${CLAUDE_PLUGIN_ROOT:-}/always-on-rules.md"

# Silent no-op if the file is missing (e.g. a broken install) — better to lose
# the rules than to block the session start.
[ -f "$RULES" ] && cat "$RULES"

# --- version stamp -----------------------------------------------------------
#
# The version the session is running, so the skills can stamp what they publish
# with it. Nothing else carries it: a transcript records the plugin *name* and
# the Claude Code version, never the plugin's, so without this a review or PR
# cannot be attributed to the prompts that produced it.
#
# Gated on `version_stamp`, and gated here rather than in the three skills
# because this note is the only thing that puts a version in front of them — no
# note leaves them nothing to decide with.
#
# *Where* to stamp lives in the three skills that publish, which are read on
# demand; this file is charged to every session and every subagent spawn. The
# literal format is the exception and stays here: a session that publishes
# without loading one of those skills has been told to stamp and, without it,
# not how — so it invents a format, and analysis reads that as a missing stamp
# in the wrong place. A dozen tokens buys the difference between a gap and a
# wrong answer.
#
# Name and version both read from the manifest, so a vendored copy stamps its
# own identity rather than this one's — emitting `dnbg-workflow` over another
# plugin's version number is the single wrong-attribution shape the stamp exists
# to rule out. One value serves as both the heading and the literal, which is
# also what keeps them from drifting apart.
#
# `jq` rather than a regex over JSON, and silently absent when `jq` is: the rules
# above still inject without it (that path is exercised by inject-rules.bats),
# and a stamp is worth less than the rules it would sit beside.
MANIFEST="${CLAUDE_PLUGIN_ROOT:-}/.claude-plugin/plugin.json"
STAMP=""
if version_stamp_enabled && [ -f "$MANIFEST" ] && command -v jq >/dev/null 2>&1; then
  STAMP=$(jq -r 'if .name and .version then "\(.name) \(.version)" else empty end' \
    "$MANIFEST" 2>/dev/null)
fi

[ -n "$STAMP" ] && cat <<EOF

## $STAMP

Stamp what you publish with \`<!-- $STAMP -->\` — \`reviewer\`, \`git-workflow\`,
and \`issue-workflow\` each say where it goes.
EOF

# --- configuration overrides -------------------------------------------------
#
# The skills state the mechanical defaults literally — `.worktrees/`,
# `assigned:agent-session` — so an unconfigured session pays nothing for these
# knobs and reads the skills as written.
# When a knob *is* set, this note is the only thing that says so, and it says it
# where both audiences see it: the skills cannot carry the configured value
# themselves, because `${user_config.*}` substitutes nothing whatsoever when an
# option is unset (see lib.sh) and would leave an unconfigured reader staring at
# a literal placeholder where a path should be.
#
# Emitted only when something is actually configured, so the default install pays
# no tokens for a note with nothing to report — the same bar the dependency
# preflight in inject-rules.sh is held to.

CONFIGURED_WORKTREE_PATH="${CLAUDE_PLUGIN_OPTION_WORKTREE_PATH:-}"
CONFIGURED_CLAIM_LABEL="${CLAUDE_PLUGIN_OPTION_CLAIM_LABEL:-}"

WORKTREE_PATH_BAD=""
CLAIM_LABEL_BAD=""
[ -n "$CONFIGURED_WORKTREE_PATH" ] &&
  WORKTREE_PATH_BAD=$(worktree_path_rejection "$CONFIGURED_WORKTREE_PATH")
[ -n "$CONFIGURED_CLAIM_LABEL" ] &&
  CLAIM_LABEL_BAD=$(claim_label_rejection "$CONFIGURED_CLAIM_LABEL")

# Rejections first. A reader who sees only the override note below would take the
# default it names as their configuration working, when in fact their value was
# thrown away — so the reason has to arrive before, not after.
if [ -n "$WORKTREE_PATH_BAD" ] || [ -n "$CLAIM_LABEL_BAD" ]; then
  printf '\n## dnbg-workflow: INVALID configuration (ignored)\n\n'
fi

[ -n "$WORKTREE_PATH_BAD" ] && cat <<EOF
The configured worktree path \`$CONFIGURED_WORKTREE_PATH\` cannot be used:
$WORKTREE_PATH_BAD. Worktrees have to stay inside the repo, where \`.gitignore\`
covers them and \`git-workflow\`'s cleanup steps resolve. **Using
\`$DEFAULT_WORKTREE_PATH\` instead** — set a repo-relative path from \`/plugin\`
to change it.
EOF

[ -n "$CLAIM_LABEL_BAD" ] && cat <<EOF
The configured claim label \`$CONFIGURED_CLAIM_LABEL\` cannot be used:
$CLAIM_LABEL_BAD. \`issue-workflow\`'s in-progress check matches the
\`$CLAIM_LABEL_NAMESPACE\` prefix rather than an enumerated list, so a label
outside it makes this plugin's claims invisible to every other claimant and
theirs invisible here — two workers on one issue, which is what the label exists
to prevent. **Using \`$DEFAULT_CLAIM_LABEL\` instead.**
EOF

WORKTREE_PATH=$(resolve_worktree_path)
CLAIM_LABEL=$(resolve_claim_label)

# Compared against the defaults rather than against "was anything set", so an
# operator who configures a knob to the value it already had gets no note. There
# is nothing to override in that case, and a note claiming otherwise would be
# noise the reader has to work out is a no-op.
if [ "$WORKTREE_PATH" != "$DEFAULT_WORKTREE_PATH" ] || [ "$CLAIM_LABEL" != "$DEFAULT_CLAIM_LABEL" ]; then
  printf '\n## dnbg-workflow: configuration overrides\n\n'
  printf 'These win over the skills. Where a skill spells out a default below and this note names something else, use what this note says.\n\n'
fi

[ "$WORKTREE_PATH" != "$DEFAULT_WORKTREE_PATH" ] && cat <<EOF
- **Worktrees live in \`$WORKTREE_PATH/\`**, not the \`$DEFAULT_WORKTREE_PATH/\`
  that \`git-workflow\` and \`reviewer\` spell out. Create them at
  \`$WORKTREE_PATH/<branch-name>\`, remove them from there, and ensure
  \`$WORKTREE_PATH\` is in \`.gitignore\`.
EOF

[ "$CLAIM_LABEL" != "$DEFAULT_CLAIM_LABEL" ] && cat <<EOF
- **The claim label is \`$CLAIM_LABEL\`**, not the \`$DEFAULT_CLAIM_LABEL\` that
  \`issue-workflow\` spells out. Use it in that skill's \`gh label create\` and
  \`gh issue edit\` calls. The check for an *existing* claim is unchanged: it
  matches the whole \`$CLAIM_LABEL_NAMESPACE\` prefix, so it still sees claims
  made under any other name in that namespace.
EOF

exit 0
