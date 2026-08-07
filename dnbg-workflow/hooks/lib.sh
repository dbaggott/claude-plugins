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
