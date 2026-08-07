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
