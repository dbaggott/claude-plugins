#!/usr/bin/env bats
#
# Unit tests for the hooks' shared helpers. These three functions decide whether
# an edit gets blocked, so every case below is a behaviour the hooks depend on
# rather than an example of how the code happens to work today.

setup() {
  # shellcheck source=../dnbg-workflow/hooks/lib.sh
  . "${BATS_TEST_DIRNAME}/../dnbg-workflow/hooks/lib.sh"
}

# --- owner_from_remote -------------------------------------------------------
# The three forms git actually emits, enumerated in lib.sh's own comment.

@test "owner_from_remote: scp-style ssh" {
  [ "$(owner_from_remote 'git@github.com:acme-corp/repo.git')" = acme-corp ]
}

@test "owner_from_remote: https" {
  [ "$(owner_from_remote 'https://github.com/acme-corp/repo.git')" = acme-corp ]
}

@test "owner_from_remote: ssh:// url" {
  [ "$(owner_from_remote 'ssh://git@github.com/acme-corp/repo.git')" = acme-corp ]
}

@test "owner_from_remote: .git suffix is optional" {
  [ "$(owner_from_remote 'https://github.com/acme-corp/repo')" = acme-corp ]
}

@test "owner_from_remote: empty input yields empty, not a crash" {
  [ -z "$(owner_from_remote '')" ]
}

# --- owner_from_repo_spec ----------------------------------------------------
# Kept separate from the remote parser precisely because `owner/repo` has no
# host to strip — the remote parser would eat the owner itself. That is the
# regression this pair of tests exists to catch.

@test "owner_from_repo_spec: bare owner/repo" {
  [ "$(owner_from_repo_spec 'acme-corp/repo')" = acme-corp ]
}

@test "owner_from_repo_spec: full https url" {
  [ "$(owner_from_repo_spec 'https://github.com/acme-corp/repo')" = acme-corp ]
}

@test "owner_from_repo_spec: github.com/ prefix without scheme" {
  [ "$(owner_from_repo_spec 'github.com/acme-corp/repo')" = acme-corp ]
}

@test "the two parsers are not interchangeable" {
  # If someone 'simplifies' by deleting one, this fails: the remote parser
  # strips the first segment as a host, which is right for a URL and wrong here.
  [ "$(owner_from_repo_spec 'acme-corp/repo')" = acme-corp ]
  [ "$(owner_from_remote   'acme-corp/repo')" != acme-corp ]
}

# --- owner_is_covered --------------------------------------------------------

@test "owner_is_covered: exact match" {
  CLAUDE_PLUGIN_OPTION_OWNERS=acme-corp run owner_is_covered acme-corp
  [ "$status" -eq 0 ]
}

@test "owner_is_covered: matches within a comma list" {
  CLAUDE_PLUGIN_OPTION_OWNERS=other,acme-corp,third run owner_is_covered acme-corp
  [ "$status" -eq 0 ]
}

@test "owner_is_covered: case-insensitive, as GitHub logins are" {
  CLAUDE_PLUGIN_OPTION_OWNERS=Acme-Corp run owner_is_covered ACME-corp
  [ "$status" -eq 0 ]
}

@test "owner_is_covered: whitespace around commas is ignored" {
  CLAUDE_PLUGIN_OPTION_OWNERS=' other , acme-corp ' run owner_is_covered acme-corp
  [ "$status" -eq 0 ]
}

@test "owner_is_covered: whole-name match — acme does not match acme-corp" {
  # The comma-wrapping exists for this. A substring match would cover repos the
  # operator never listed, which is the dangerous direction to be wrong in.
  CLAUDE_PLUGIN_OPTION_OWNERS=acme run owner_is_covered acme-corp
  [ "$status" -ne 0 ]
  CLAUDE_PLUGIN_OPTION_OWNERS=acme-corp run owner_is_covered acme
  [ "$status" -ne 0 ]
}

@test "owner_is_covered: empty list covers nothing (fail-open default)" {
  # A fresh install must block nothing until the operator opts in.
  CLAUDE_PLUGIN_OPTION_OWNERS='' run owner_is_covered acme-corp
  [ "$status" -ne 0 ]
}

@test "owner_is_covered: unset list covers nothing" {
  run env -u CLAUDE_PLUGIN_OPTION_OWNERS bash -c \
    ". '${BATS_TEST_DIRNAME}/../dnbg-workflow/hooks/lib.sh'; owner_is_covered acme-corp"
  [ "$status" -ne 0 ]
}

@test "owner_is_covered: empty owner is never covered" {
  CLAUDE_PLUGIN_OPTION_OWNERS=acme-corp run owner_is_covered ''
  [ "$status" -ne 0 ]
}

# --- host_from_remote --------------------------------------------------------

@test "host_from_remote: all four remote forms" {
  [ "$(host_from_remote 'git@github.com:acme/repo.git')"          = github.com ]
  [ "$(host_from_remote 'https://github.com/acme/repo.git')"      = github.com ]
  [ "$(host_from_remote 'ssh://git@github.com/acme/repo.git')"    = github.com ]
  [ "$(host_from_remote 'ssh://git@github.com:22/acme/repo.git')" = github.com ]
}

@test "host_from_remote: non-github hosts are reported as themselves" {
  [ "$(host_from_remote 'https://gitlab.com/acme/repo.git')"    = gitlab.com ]
  [ "$(host_from_remote 'https://bitbucket.org/acme/repo')"     = bitbucket.org ]
  [ "$(host_from_remote 'git@github.mycorp.com:acme/repo.git')" = github.mycorp.com ]
}

@test "host_from_remote: the host is lowercased" {
  # Hostnames are case-insensitive by DNS and git stores the URL verbatim, so
  # whatever was typed at clone time reaches the comparison. Without this an
  # ordinary GitHub remote fails the github.com check and the gate silently
  # does not fire on a repo the operator explicitly listed.
  [ "$(host_from_remote 'git@GitHub.com:acme/repo.git')"     = github.com ]
  [ "$(host_from_remote 'https://GITHUB.COM/acme/repo.git')" = github.com ]
  [ "$(host_from_remote 'ssh://git@GitHub.COM:22/acme/r')"   = github.com ]
}

@test "remote_is_covered: mixed-case github.com is still covered" {
  export CLAUDE_PLUGIN_OPTION_OWNERS=acme
  for u in 'git@GitHub.com:acme/repo.git' \
           'https://GITHUB.COM/acme/repo.git'; do
    run remote_is_covered "$u"
    [ "$status" -eq 0 ]
  done
}

@test "remote_is_covered: case-folding does not accidentally cover another host" {
  CLAUDE_PLUGIN_OPTION_OWNERS=acme run remote_is_covered 'https://GITLAB.COM/acme/repo.git'
  [ "$status" -ne 0 ]
}

@test "host_from_remote: a local path has no host" {
  [ -z "$(host_from_remote '/local/path/repo')" ]
}

@test "owner_from_remote: an explicit port is not the owner" {
  # Regression. The host strip used to consume `github.com:` and leave
  # `22/acme/repo`, so a legitimately covered repo read as uncovered and
  # silently lost its gate — the opposite direction of the host bug.
  [ "$(owner_from_remote 'ssh://git@github.com:22/acme/repo.git')" = acme ]
}

@test "owner_from_remote: the port rule does not eat an scp-style owner" {
  # `github.com:acme/repo` uses the same colon for a path, not a port. The
  # digits-only restriction is what keeps these two apart.
  [ "$(owner_from_remote 'git@github.com:acme/repo.git')" = acme ]
  [ "$(owner_from_remote 'git@github.com:123org/repo.git')" = 123org ]
}

# --- remote_is_covered -------------------------------------------------------

@test "remote_is_covered: every github.com form is covered" {
  export CLAUDE_PLUGIN_OPTION_OWNERS=acme
  for u in 'git@github.com:acme/repo.git' \
           'https://github.com/acme/repo.git' \
           'ssh://git@github.com/acme/repo.git' \
           'ssh://git@github.com:22/acme/repo.git'; do
    run remote_is_covered "$u"
    [ "$status" -eq 0 ]
  done
}

@test "remote_is_covered: a same-named owner on another host is not covered" {
  # The bug this function exists for: listing a GitHub org must not gate a
  # same-named org on GitLab, where the hooks would block while every skill
  # tells the agent to run gh commands that cannot work.
  export CLAUDE_PLUGIN_OPTION_OWNERS=acme
  for u in 'https://gitlab.com/acme/repo.git' \
           'https://bitbucket.org/acme/repo' \
           'git@bitbucket.org:acme/repo.git'; do
    run remote_is_covered "$u"
    [ "$status" -ne 0 ]
  done
}

@test "remote_is_covered: GitHub Enterprise is deliberately not covered" {
  CLAUDE_PLUGIN_OPTION_OWNERS=acme run remote_is_covered 'git@github.mycorp.com:acme/repo.git'
  [ "$status" -ne 0 ]
}

@test "remote_is_covered: a local path is never covered" {
  CLAUDE_PLUGIN_OPTION_OWNERS=acme run remote_is_covered '/local/path/repo'
  [ "$status" -ne 0 ]
}

@test "remote_is_covered: right host, wrong owner" {
  CLAUDE_PLUGIN_OPTION_OWNERS=other run remote_is_covered 'git@github.com:acme/repo.git'
  [ "$status" -ne 0 ]
}
