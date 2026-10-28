#!/usr/bin/env bash
# A git credential helper that answers with a role's credential, through the
# role resolver, so a worktree's pushes go out under that role and a session
# that outlives one token keeps pushing: every `get` mints afresh.
#
#   git-credential-as-role.sh <role> get|store|erase     # git runs this
#   git-credential-as-role.sh --install <role> [<worktree>]
#
# ## As a helper
#
# `get` reads git's request on stdin. It needs `path`, which git sends only
# under `credential.useHttpPath=true`, because the repo, not the host, picks
# the App installation. It asks `as-role.sh <role> <host>/<path>` and answers:
#   - the role has an App: `username=x-access-token` and the minted token;
#   - the role falls back to the operator: whatever the operator's
#     `gh auth git-credential get` answers;
#   - anything else, a configured role whose mint fails included: `quit=1`,
#     which stops git without trying another helper or prompting, after the
#     resolver's reason on stderr. Never the operator's credential.
# The resolver's own `as-role.sh: result=…` line reaches stderr, which git
# shows, so each push says whom it ran as. `store` and `erase` do nothing:
# nothing is kept, so there is nothing to store or forget.
#
# ## --install
#
# Points <worktree> (default: the current directory) at this helper, in that
# worktree's own config, so the main checkout keeps the operator's credential:
#   extensions.worktreeConfig=true        in the repository's shared config,
#                                         which is what allows the rest; left
#                                         unwritten when already true
#   credential.helper= then this helper   the empty entry clears every helper
#                                         read before it, `credential.<url>.helper`
#                                         ones included (gitcredentials(7))
#   credential.useHttpPath=true
#   remote.origin.pushurl=https://…       only when origin is an SSH URL, which
#                                         would never ask a credential helper
# One result line, then exit 0:
#   result=OK worktree=<path> pushurl=<url|origin>
#   result=ERROR reason=bad-args|unknown-role|unsafe-helper-path|unsupported-forge|not-a-worktree|main-worktree|bare-repo|no-origin|git-config|push-not-https
# `unsafe-helper-path` means this script's own path holds a character the shell
# git runs the helper through would read specially: `"`, `$`, a backtick, a
# backslash or a newline.
# `push-not-https` means a push from the worktree would still skip the helper:
# a pushurl in the shared config, which a worktree's own cannot replace, or an
# `insteadOf`/`pushInsteadOf` rule turning the HTTPS URL back into SSH. The
# config is left written; the push it names would go out as whoever owns that
# SSH key, so stop rather than push.
# Run it again on every worktree you take up: it is idempotent, and the helper
# path it records is this copy's, which a plugin update can remove.
#
# ⚠️ THE FORGE IS ASSUMED TO BE GITHUB. https://github.com/dbaggott/claude-plugins/issues/149
# replaces the constant below with host detection. Two parts are GitHub's: the
# `x-access-token` username an installation token pushes under, and the
# operator's `gh auth git-credential`. The resolver already refuses a host it
# has no backend for.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SELF="$HERE/$(basename "$0")"
# shellcheck source=./lib-role.sh
. "$HERE/lib-role.sh"

FORGE="${FORGE:-github}"

fail() { echo "result=ERROR reason=$1"; [ -z "${2:-}" ] || printf '%s\n' "$2" >&2; exit 0; }

# A config write --install could not make: the file, git's own reason, and the
# likely cause, since a sandboxed session hits this on its first install.
config_fail() {  # <path> <what it is> <git's stderr>
  fail git-config "could not write $1, $2: $(printf '%s' "${3:-no reason given}" | tr '\n' ' ')
A sandbox is a likely cause: Claude Code's sandbox refuses every write to a .git/config, and any write outside the directories it allows. If so, run this call outside the sandbox."
}

# An SSH remote's HTTPS twin: git@host:owner/name(.git) or ssh://[user@]host[:port]/owner/name.
https_of() {  # <url> -> url, or nothing when it is not SSH
  local u="$1" rest host path
  case "$u" in
    ssh://*) rest="${u#ssh://}"; rest="${rest#*@}"; host="${rest%%/*}"; host="${host%%:*}"; path="${rest#*/}" ;;
    *://*) return 0 ;;
    *@*:*) rest="${u#*@}"; host="${rest%%:*}"; path="${rest#*:}" ;;
    *) return 0 ;;
  esac
  path="${path%.git}"
  printf 'https://%s/%s.git\n' "$host" "$path"
}

install() {  # <role> [<worktree>]
  local role="$1" wt="${2:-$PWD}" gitdir common origin push err
  [ -n "$role" ] || fail bad-args
  role_valid "$role" || fail unknown-role "'$role' is not a role: no $ROLES_DIR/$role/permissions.json"
  # The helper entry is `!"<path>" <role>`, which git hands to a shell: the first
  # four are what a double-quoted string still expands or ends on, and a newline
  # would break the entry. Refused rather than escaped, since a real install path
  # does not carry them.
  case "$SELF" in
    *[\"\$\`\\]*|*$'\n'*) fail unsafe-helper-path "the helper's path, $(printf '%q' "$SELF"), contains \", \$, \`, \\ or a newline, which the shell git runs it through would read; install the plugin under a path without them" ;;
  esac
  [ "$FORGE" = github ] || fail unsupported-forge
  gitdir=$(git -C "$wt" rev-parse --absolute-git-dir 2>/dev/null) || fail not-a-worktree "'$wt' is not inside a git worktree"
  common=$(cd "$wt" && cd "$(git rev-parse --git-common-dir)" && pwd -P)
  # The main checkout's git dir is the common one. Configuring it would move
  # every push in the repository onto the role, the operator's own included.
  [ "$(cd "$gitdir" && pwd -P)" != "$common" ] \
    || fail main-worktree "'$wt' is the main checkout; install on a worktree made with \`git worktree add\`"
  # git's own rule for the extension: a core.bare or core.worktree in the
  # shared config would then apply to every worktree.
  if [ "$(git config --file "$common/config" --get core.bare 2>/dev/null)" = true ] \
      || git config --file "$common/config" --get core.worktree >/dev/null 2>&1; then
    fail bare-repo "$common/config sets core.bare=true or core.worktree, which extensions.worktreeConfig would apply to every worktree; move it to the main worktree's config.worktree first"
  fi
  origin=$(git -C "$wt" remote get-url origin 2>/dev/null) || fail no-origin "'$wt' has no origin remote"
  # Written only when not already true: a sandboxed session cannot write
  # .git/config, so skipping a write that changes nothing lets every install
  # after a repository's first one run sandboxed.
  if [ "$(git config --file "$common/config" --includes --type=bool --get extensions.worktreeConfig 2>/dev/null)" != true ]; then
    err=$(git -C "$wt" config extensions.worktreeConfig true 2>&1 >/dev/null) \
      || config_fail "$common/config" "the repository's shared config, for extensions.worktreeConfig" "$err"
  fi
  if ! err=$({ { git -C "$wt" config --worktree --unset-all credential.helper || [ $? = 5 ]; } \
      && git -C "$wt" config --worktree credential.helper '' \
      && git -C "$wt" config --worktree --add credential.helper "!\"$SELF\" $role" \
      && git -C "$wt" config --worktree credential.useHttpPath true; } 2>&1 >/dev/null); then
    config_fail "$gitdir/config.worktree" "$wt's own config" "$err"
  fi
  push=$(https_of "$origin")
  # A shared pushurl already says where pushes go, and one set here would only
  # be added beside it.
  if [ -n "$push" ] && ! git config --file "$common/config" --get remote.origin.pushurl >/dev/null 2>&1; then
    err=$(git -C "$wt" config --worktree remote.origin.pushurl "$push" 2>&1 >/dev/null) \
      || config_fail "$gitdir/config.worktree" "$wt's own config, for its push URL" "$err"
  else
    push=""
  fi
  # What git will actually push to, after every rewrite rule.
  local url bad=""
  while IFS= read -r url; do
    case "$url" in https://github.com/*) ;; *) bad="${bad:+$bad, }$url" ;; esac
  done < <(git -C "$wt" remote get-url --push --all origin 2>/dev/null)
  [ -z "$bad" ] || fail push-not-https "$wt would push to $bad, which the $role helper never answers; set an https://github.com/ push URL (and drop any insteadOf rule rewriting it) before pushing"
  echo "result=OK worktree=$wt pushurl=${push:-origin}"
}

# Runs under the resolver, which has put the role's credential in place or, for
# a role falling back, removed every token so `gh` uses the operator's own auth.
answer() {
  if [ -n "${GH_TOKEN:-}" ]; then
    printf 'username=x-access-token\npassword=%s\n' "$GH_TOKEN"
  else
    exec gh auth git-credential get
  fi
}

# Stops git: no other helper, no prompt.
quit() { printf '%s\n' "git-credential-as-role.sh: $1" >&2; echo "quit=1"; exit 0; }

get() {  # <role>
  local role="$1" input line host="" path="" proto="" out=""
  input=$(cat)
  while IFS= read -r line; do
    case "$line" in
      protocol=*) proto="${line#protocol=}" ;;
      host=*) host="${line#host=}" ;;
      path=*) path="${line#path=}" ;;
    esac
  done <<<"$input"
  [ "$FORGE" = github ] || quit "unsupported-forge: no backend for '$FORGE'"
  [ "$proto" = https ] || quit "only https remotes are answered, not '$proto'"
  [ -n "$path" ] || quit "git sent no repository path; set credential.useHttpPath=true (run --install on this worktree)"
  # The repository is the path's first two segments: Git LFS asks for
  # `<owner>/<name>.git/info/lfs`.
  path="${path#/}"
  case "$path" in */*) ;; *) quit "'$path' names no owner and repository" ;; esac
  local owner="${path%%/*}" name="${path#*/}"
  name="${name%%/*}"; path="$owner/${name%.git}"
  out=$(printf '%s\n' "$input" | "$HERE/as-role.sh" "$role" "$host/$path" -- "$SELF" --answer) \
    || quit "no credential for $host/$path as the $role role (above); not using any other"
  case "$out" in
    *password=*) printf '%s\n' "$out" ;;
    *) quit "the $role role's credential for $host/$path came back empty" ;;
  esac
}

case "${1:-}" in
  --install) shift; install "$@" ;;
  --answer) answer ;;
  -*|'') fail bad-args "usage: git-credential-as-role.sh <role> get|store|erase, or --install <role> [<worktree>]" ;;
  *)
    [ "$#" -eq 2 ] || fail bad-args
    case "$2" in
      get) get "$1" ;;
      store|erase) cat >/dev/null ;;
      *) ;;   # an operation git adds later: answering nothing is what the protocol asks
    esac ;;
esac
