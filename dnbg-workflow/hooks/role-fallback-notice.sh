#!/usr/bin/env bash
# SessionStart hook: name each agent role that would act as the operator's own
# account because it has no App of its own, so the fallback tier is never
# silent. Reads configuration presence only (`as-role.sh --fallbacks`), with no
# network call. Prints nothing when no role falls back, or when the resolver
# cannot answer: the resolver itself reports that at the first role call.
set -u

LINE=$("$(dirname "$0")/../scripts/as-role.sh" --fallbacks 2>/dev/null) || exit 0
case "$LINE" in
  "result=OK roles=none"|"") ;;
  result=OK\ roles=*)
    ROLES="${LINE#result=OK roles=}"
    cat <<EOM

## dnbg-workflow: roles acting as your own account

These roles have no GitHub App set up, so their GitHub writes post under your
login (the fallback tier): ${ROLES//,/, }. The \`reviewer-setup\` skill creates
their Apps.
EOM
    ;;
  "result=ERROR reason=shared-identity")
    cat <<'EOM'

## dnbg-workflow: two roles share one GitHub App

Every role call fails with `shared-identity`, naming the pair, until each role
has its own App. The `reviewer-setup` skill creates one.
EOM
    ;;
esac
exit 0
