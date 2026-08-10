#!/usr/bin/env bash
# Shared helpers for the enforcement hooks. Sourced, never executed.
#
# Both blocking hooks answer the same question — "is this repo one the operator
# asked me to enforce on?" — from two different inputs (a git remote, a `gh
# --repo` argument), so the owner match lives here rather than in each script.

# Three separate edges have now been found in the layered strips below — a port
# eating the owner, an uppercase host, an uppercase scheme — each fixed and
# pinned by a fixture. The expressions are correct as far as they are tested,
# but the accumulation is the signal: if a *fourth* edge turns up, stop patching
# and parse the URL once into (scheme, user, host, port, path), then answer both
# questions from the parts.
#
# Owner segment of a git remote URL. Handles the forms git emits:
#   git@github.com:owner/repo.git
#   https://github.com/owner/repo.git
#   ssh://git@github.com/owner/repo.git
#   ssh://git@github.com:22/owner/repo.git   (explicit port)
#
# The optional `(:[0-9]+)?` is what makes the port form work. Without it the
# host strip consumes `github.com:` and leaves `22/owner/repo`, so the port
# becomes the owner — a legitimately covered repo then reads as uncovered and
# silently loses its gate. Restricted to digits so it cannot eat the `owner`
# in the scp-style `github.com:owner/repo`, where the same colon separates a
# host from a path rather than from a port.
owner_from_remote() {
  printf '%s\n' "${1:-}" \
    | sed -E 's#\.git$##; s#^[a-zA-Z+]+://##; s#^[^/@]+@##; s#^[^/:]+(:[0-9]+)?[:/]##; s#/.*$##'
}

# Host segment of the same URL. Everything before the first `:` or `/` once the
# scheme and any `user@` are gone; empty for a local path, which has no host and
# is therefore never covered.
#
# Lowercased, because hostnames are case-insensitive by DNS and git stores a
# remote URL exactly as it was typed — it never normalises the host. Without
# this, a perfectly ordinary `git@GitHub.com:owner/repo.git` fails the
# `github.com` comparison below and the gate silently does not fire on a repo
# the operator explicitly listed. Normalising here rather than at the comparison
# keeps it true for any future caller.
host_from_remote() {
  printf '%s\n' "${1:-}" \
    | sed -E 's#^[a-zA-Z+]+://##; s#^[^/@]+@##; s#[:/].*$##' \
    | tr '[:upper:]' '[:lower:]'
}

# Owner segment of a `gh --repo` argument, which is either `owner/repo` or a
# full URL. Kept separate from owner_from_remote: `owner/repo` has no host to
# strip, so the remote parser would strip the owner itself.
owner_from_repo_spec() {
  printf '%s\n' "${1:-}" \
    | sed -E 's#^[a-z+]+://[^/]+/##; s#^github\.com/##; s#/.*$##'
}

# Is this owner in the operator's configured list? The list comes from the
# plugin's `owners` userConfig, which Claude Code exports to hook processes as
# CLAUDE_PLUGIN_OPTION_OWNERS.
#
# An unset or empty list means no repo is covered, so a fresh install blocks
# nothing until the operator opts in. Failing open is the right default for a
# hook that can halt an edit: someone who installed this for the skills should
# not discover the config field by having their work blocked.
# Matching is case-insensitive (GitHub logins are) and whitespace around the
# commas is ignored. Comparing comma-wrapped strings rather than splitting the
# list keeps this correct under any shell — unquoted word splitting is a bash
# behavior zsh does not share, and a sourced helper should not depend on it.
# GitHub logins contain no commas or whitespace, so stripping both is safe.
owner_is_covered() {
  local owner list
  owner=$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
  list=$(printf '%s' "${CLAUDE_PLUGIN_OPTION_OWNERS:-}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
  [ -n "$owner" ] && [ -n "$list" ] || return 1

  case ",${list}," in
    *",${owner},"*) return 0 ;;
  esac
  return 1
}

# Is this remote a repo the operator asked to enforce on? Both the host and the
# owner have to match, and this exists so that no *remote* is judged on its owner
# alone — a `git remote get-url` result has a host, so the host is always part of
# the question.
#
# `gh --repo` arguments are the deliberate exception and still go through
# `owner_is_covered` directly: `owner/repo` carries no host, and `gh` is GitHub
# by definition, so there is nothing to check.
#
# The host check is not pedantry. Without it the owner parser happily reports
# `acme-corp` for `gitlab.com/acme-corp/api`, so listing a GitHub org silently
# gates a same-named org on another host — where the hooks would block edits
# while every skill instructs the agent to run `gh` commands that cannot work
# there. A half-working state is worse than either extreme.
#
# GitHub Enterprise (`github.mycorp.com`) is deliberately *not* covered. That is
# the safe direction to be wrong in — under-enforcing rather than mis-enforcing —
# and the skills' `gh` usage has never been audited against Enterprise anyway.
remote_is_covered() {
  [ "$(host_from_remote "${1:-}")" = "github.com" ] || return 1
  owner_is_covered "$(owner_from_remote "${1:-}")"
}

# --- the mechanical opinions --------------------------------------------------
#
# Two userConfig knobs move where worktrees live and what the claim label is
# called. Both resolve here, so the gate that prints a path and the session-start
# note that announces one can never disagree about what this session is using.
#
# ⚠️ THE MANIFEST'S `default` FIELD DOES NOT SUPPLY THESE, and the reference's
# one-line gloss for it ("Value used when the user provides nothing") reads as if
# it does. It applies when the user clears a field in the configuration dialog —
# not when the option was never configured at all. An option nobody has touched
# substitutes nothing into skill content and exports no
# CLAUDE_PLUGIN_OPTION_<KEY> to a hook, both verified against v2.1.226. That is
# the state of every existing install the moment a key is added to the manifest,
# and of every fresh install whose owner never opens the dialog, so it is the
# common case rather than the edge one. The defaults therefore have to live
# somewhere that runs; they live here. tests/coupling.bats pins them against the
# manifest so the value the dialog offers and the value an unconfigured session
# actually gets cannot drift apart.
DEFAULT_WORKTREE_PATH='.worktrees'
DEFAULT_CLAIM_LABEL='assigned:agent-session'

# The namespace every claim label has to sit in. `issue-workflow`'s in-progress
# check matches this prefix rather than an enumerated list, deliberately, so that
# any claimant — another agent, a bot, a teammate's tooling — is seen without
# this plugin knowing about it. A label outside the namespace breaks that in both
# directions at once: this plugin's claims stop being visible to other tools, and
# theirs stop being visible here. Both failures are silent, and what they produce
# is two workers on one issue — the exact collision the label exists to prevent.
CLAIM_LABEL_NAMESPACE='assigned:'

# Why a configured worktree path cannot be used, as a sentence fragment that
# completes "…is unusable: %s." Empty output means it is usable.
#
# Repo-relative only. An absolute path — or a `~` one, which is absolute in the
# only sense that matters here — puts worktrees where `.gitignore` cannot cover
# them and where `git-workflow`'s cleanup steps stop resolving. A `..` segment
# escapes the same way while looking relative, so it is rejected on the same
# grounds rather than left as the one hole in the rule.
worktree_path_rejection() {  # <configured-value>
  # SC2088 reads a quoted `~` as a tilde that failed to expand. Here it is a
  # `case` pattern matching the literal character the operator typed, which is
  # the only thing git would see either — so not expanding it is the point.
  # shellcheck disable=SC2088
  case "${1:-}" in
    /*) printf 'it is an absolute path' ;;
    '~' | '~/'*) printf 'it is a home-relative path' ;;
    '..' | '../'* | *'/..' | *'/../'*) printf "it contains a \`..\` segment that escapes the repo" ;;
  esac
}

# Why a configured claim label cannot be used, same contract as above.
#
# The bare-namespace case is checked first because `case` takes the first match
# and `assigned:` matches the prefix pattern below it. A label of exactly
# `assigned:` passes a naive prefix test while naming no claimant at all.
claim_label_rejection() {  # <configured-value>
  case "${1:-}" in
    "$CLAIM_LABEL_NAMESPACE")
      printf "it is the bare \`%s\` namespace with nothing after the colon" "$CLAIM_LABEL_NAMESPACE" ;;
    "$CLAIM_LABEL_NAMESPACE"*) ;;
    *) printf "it is outside the \`%s\` namespace" "$CLAIM_LABEL_NAMESPACE" ;;
  esac
}

# The worktree root this session uses: the configured value when it is set and
# usable, the default otherwise. A rejected value falls back rather than failing
# the hook — `inject-rules.sh` is where the operator is told why, once per
# session, and a gate that blocked every edit over a bad config would punish the
# wrong thing.
#
# Trailing slashes are stripped so every caller can join with a single `/`, and
# so that `.worktrees` and `.worktrees/` are not two different configurations.
# Stripping before the emptiness test is what keeps a value of `/` (which strips
# to nothing) from resolving to an empty root that would silently mean the repo
# itself.
resolve_worktree_path() {
  local value="${CLAUDE_PLUGIN_OPTION_WORKTREE_PATH:-}"
  while [ "${value%/}" != "$value" ]; do value="${value%/}"; done
  if [ -n "$value" ] && [ -z "$(worktree_path_rejection "$value")" ]; then
    printf '%s' "$value"
  else
    printf '%s' "$DEFAULT_WORKTREE_PATH"
  fi
}

# The claim label this session uses. Same fallback contract as above.
resolve_claim_label() {
  local value="${CLAUDE_PLUGIN_OPTION_CLAIM_LABEL:-}"
  if [ -n "$value" ] && [ -z "$(claim_label_rejection "$value")" ]; then
    printf '%s' "$value"
  else
    printf '%s' "$DEFAULT_CLAIM_LABEL"
  fi
}
