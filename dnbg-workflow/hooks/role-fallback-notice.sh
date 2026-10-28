#!/usr/bin/env bash
# SessionStart hook: name each agent role that would act as the operator's own
# account because it has no App of its own, so the fallback tier is never
# silent. Reads configuration presence only (`as-role.sh --fallbacks`), with no
# network call. Also names the configuration refusals that fail every role
# call; prints nothing for any other answer the resolver cannot give, which it
# reports itself at the first role call.
set -u

AS_ROLE="$(dirname "$0")/../scripts/as-role.sh"
LINE=$("$AS_ROLE" --fallbacks 2>/dev/null) || exit 0
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
  "result=ERROR reason=bad-config")
    # The refusal's detail, naming the role and variable, is on stderr.
    DETAIL=$("$AS_ROLE" --fallbacks 2>&1 >/dev/null)
    cat <<EOM

## dnbg-workflow: a role's config directory is refused

${DETAIL}
Every role call fails with \`bad-config\` until that variable changes.
EOM
    ;;
esac
exit 0
