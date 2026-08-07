#!/usr/bin/env bash
# Shared helpers for the enforcement hooks. Sourced, never executed.
#
# Both blocking hooks answer the same question — "is this repo one the operator
# asked me to enforce on?" — from two different inputs (a git remote, a `gh
# --repo` argument), so the owner match lives here rather than in each script.

# Owner segment of a git remote URL. Handles the three forms git emits:
#   git@github.com:owner/repo.git
#   https://github.com/owner/repo.git
#   ssh://git@github.com/owner/repo.git
owner_from_remote() {
  printf '%s\n' "${1:-}" \
    | sed -E 's#\.git$##; s#^[a-z+]+://##; s#^[^/@]+@##; s#^[^/:]+[:/]##; s#/.*$##'
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
