#!/usr/bin/env bash
# Filing an issue. The gate fires first, because an issue written without the
# skill is the failure the gate exists to prevent: a body the next session
# cannot work from.
#
# A reenactment, except the BLOCKED message — that is produced live by the real
# check-issue-create.sh, from a real payload. See lib-demo.sh.
set -euo pipefail
# shellcheck source=./lib-demo.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-demo.sh"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export CLAUDE_PLUGIN_OPTION_OWNERS=dbaggott

say()  { printf '%s\n' "$1"; }

printf '%s❯%s file that symlink bug you just hit\n' "$C_USER" "$C_OFF"
beat 1.5

say "${C_TOOL}● Bash${C_OFF}   gh issue create --repo dbaggott/claude-plugins ..."
beat 1.0
printf '\n'

# Real hook, real payload, real exit code — this is the one part not scripted.
TRANSCRIPT=$(mktemp)
printf '{}\n' > "$TRANSCRIPT"
printf '{"tool_name":"Bash","tool_input":{"command":"gh issue create --repo dbaggott/claude-plugins --title x --body y"},"transcript_path":"%s","cwd":"%s"}' \
  "$TRANSCRIPT" "$ROOT" | bash "$ROOT/dnbg-workflow/hooks/check-issue-create.sh" || true
rm -f "$TRANSCRIPT"
beat 4.5

printf '\n'
say "${C_TOOL}● Skill${C_OFF}  dnbg-workflow:issue-workflow"
beat 1.2
say "${C_SAY}● Verifying the anchors before I write them down.${C_OFF}"
beat 0.8
say "${C_TOOL}● Read${C_OFF}   dnbg-workflow/hooks/check-worktree.sh:42"
beat 0.7
say "${C_TOOL}● Bash${C_OFF}   git ls-files --full-name --error-unmatch  ${C_DIM}# candidate fix${C_OFF}"
beat 1.4

printf '\n'
say "${C_TOOL}● Bash${C_OFF}   gh issue create --label bug --label area:hooks"
beat 1.0
say "${C_DIM}         created${C_OFF}"
beat 1.2

printf '\n'
say "${C_SAY}  The body carries what a cold reader needs:${C_OFF}"
beat 0.5
say "${C_DIM}    · the defect, with the line that causes it${C_OFF}"
beat 0.4
say "${C_DIM}    · a reproduction, run rather than described${C_OFF}"
beat 0.4
say "${C_DIM}    · a proposed fix, and the alternative rejected${C_OFF}"
beat 0.4
say "${C_DIM}    · acceptance criteria runnable at this issue's end${C_OFF}"
beat 0.4
say "${C_DIM}    · cross-references labelled required vs optional${C_OFF}"
beat 1.2
printf '\n'
say "${C_SAY}  So resolving it costs one read, not a link crawl.${C_OFF}"
beat 1.4
printf '\n'
say "${C_SAY}  Filed:${C_OFF} ${C_USER}https://github.com/dbaggott/claude-plugins/issues/97${C_OFF}"
beat 5.0
