#!/usr/bin/env bats
#
# The two mechanical knobs, at the level where they resolve: lib.sh.
#
# What makes these worth pinning is that the fallback is *ours*. The manifest's
# `default` field looks like it supplies one and does not — an option nobody has
# configured substitutes nothing into skill content and exports no
# CLAUDE_PLUGIN_OPTION_<KEY> to a hook, so every existing install sits in exactly
# that state the moment a key is added. lib.sh's defaults are the only thing
# standing between that state and a session told to create its worktrees in a
# directory called `${user_config.worktree_path}`.

LIB="${BATS_TEST_DIRNAME}/../dnbg-workflow/hooks/lib.sh"

setup() {
  # shellcheck source=../dnbg-workflow/hooks/lib.sh
  . "$LIB"
  unset CLAUDE_PLUGIN_OPTION_WORKTREE_PATH CLAUDE_PLUGIN_OPTION_CLAIM_LABEL
}

# Each resolve runs in a subshell with the option set, so a configured value can
# never leak into the next assertion. A bare `VAR=x resolve_...` prefix would be
# shorter and is not portable for a *function* call — POSIX has the assignment
# persist afterwards, and bash follows that in POSIX mode — which is precisely
# the leak this avoids.
with_worktree_path() {  # <value>
  ( export CLAUDE_PLUGIN_OPTION_WORKTREE_PATH="$1"; resolve_worktree_path )
}

with_claim_label() {  # <value>
  ( export CLAUDE_PLUGIN_OPTION_CLAIM_LABEL="$1"; resolve_claim_label )
}

# --- defaults ----------------------------------------------------------------

@test "an unconfigured session resolves both knobs to the documented defaults" {
  # The whole zero-config contract in one test: behavior identical to the plugin
  # before the knobs existed.
  [ "$(resolve_worktree_path)" = ".worktrees" ]
  [ "$(resolve_claim_label)" = "assigned:agent-session" ]
}

@test "an empty value is the same as unset" {
  # Clearing the field in the configuration dialog stores an empty string rather
  # than removing the key, so this is a state a real install reaches.
  [ "$(with_worktree_path '')" = ".worktrees" ]
  [ "$(with_claim_label '')" = "assigned:agent-session" ]
}

@test "the claim label default is the one issue-workflow claims with" {
  # Pinned by value, not by comparison against the skill: making the name a knob
  # must not quietly revert the default to the vendor-named label it replaced.
  [ "$DEFAULT_CLAIM_LABEL" = "assigned:agent-session" ]
  [ "$DEFAULT_CLAIM_LABEL" != "assigned:claude-code" ]
}

# --- worktree path -----------------------------------------------------------

@test "a configured repo-relative worktree path is used" {
  [ "$(with_worktree_path 'wt')" = "wt" ]
  [ "$(with_worktree_path 'build/wt')" = "build/wt" ]
}

@test "trailing slashes are stripped so callers can join with one slash" {
  # `.worktrees` and `.worktrees/` are one configuration, not two. Without this
  # the block message renders `wt//<branch-name>`.
  [ "$(with_worktree_path 'wt/')" = "wt" ]
  [ "$(with_worktree_path 'wt///')" = "wt" ]
}

@test "an absolute worktree path is rejected and falls back to the default" {
  [ -n "$(worktree_path_rejection '/tmp/wt')" ]
  [ "$(with_worktree_path '/tmp/wt')" = ".worktrees" ]
}

@test "a home-relative worktree path is rejected" {
  # `~/wt` is absolute in the only sense that matters here, and git would take it
  # literally — creating a directory actually named `~` inside the repo.
  [ -n "$(worktree_path_rejection '~/wt')" ]
  [ -n "$(worktree_path_rejection '~')" ]
  [ "$(with_worktree_path '~/wt')" = ".worktrees" ]
}

@test "a worktree path with a .. segment is rejected wherever the segment sits" {
  # Relative-looking and still outside the repo. Each position is its own pattern
  # in the case, so each one is checked.
  [ -n "$(worktree_path_rejection '..')" ]
  [ -n "$(worktree_path_rejection '../wt')" ]
  [ -n "$(worktree_path_rejection 'build/..')" ]
  [ -n "$(worktree_path_rejection 'build/../../wt')" ]
  [ "$(with_worktree_path '../wt')" = ".worktrees" ]
}

@test "a path merely containing dots is not mistaken for a .. escape" {
  # The rejection is on the `..` path *segment*. A directory whose name happens to
  # contain dots is ordinary, and rejecting it would be a false positive with no
  # workaround available to the operator.
  [ -z "$(worktree_path_rejection '.worktrees')" ]
  [ -z "$(worktree_path_rejection 'a..b')" ]
  [ -z "$(worktree_path_rejection 'wt/a..b')" ]
  [ "$(with_worktree_path 'a..b')" = "a..b" ]
}

@test "a worktree path that would render an unrunnable command is rejected" {
  # The value is interpolated into the block message and the session-start note,
  # both of which an agent retypes as a shell command. `my wt` splits into two
  # arguments, so git reads `wt/<branch-name>` as a commit-ish and creates
  # nothing; `-x` is read as an option. Same failure shape as an escaping path —
  # a configured value producing an instruction that cannot work.
  [ -n "$(worktree_path_rejection 'my wt')" ]
  [ -n "$(worktree_path_rejection '-x')" ]
  [ "$(with_worktree_path 'my wt')" = ".worktrees" ]
  [ "$(with_worktree_path '-x')" = ".worktrees" ]
}

@test "a worktree path carrying shell metacharacters is rejected" {
  # Worse than unrunnable: the block message is read as an instruction, so a `;`
  # or a `$(` turns it into a *different* command rather than a broken one.
  [ -n "$(worktree_path_rejection ';rm -rf x')" ]
  [ -n "$(worktree_path_rejection 'wt$(id)')" ]
  [ -n "$(worktree_path_rejection 'wt*')" ]
  [ -n "$(worktree_path_rejection "$(printf 'a\nb')")" ]
  [ "$(with_worktree_path ';rm -rf x')" = ".worktrees" ]
}

@test "the character rule does not reject the paths people actually use" {
  # The rule has to stay a guard rather than becoming a second source of false
  # rejections — the default itself has to pass it.
  [ -z "$(worktree_path_rejection '.worktrees')" ]
  [ -z "$(worktree_path_rejection 'wt')" ]
  [ -z "$(worktree_path_rejection 'build/wt')" ]
  [ -z "$(worktree_path_rejection '.git/wt')" ]
  [ -z "$(worktree_path_rejection 'my-wt_2')" ]
}

@test "a path of only slashes falls back rather than resolving to the repo root" {
  # Stripping runs before the emptiness test for exactly this: `/` strips to
  # nothing, and an empty root would silently mean the repo itself — every
  # worktree created over the main checkout.
  [ "$(with_worktree_path '/')" = ".worktrees" ]
  [ "$(with_worktree_path '///')" = ".worktrees" ]
}

# --- claim label -------------------------------------------------------------

@test "a configured claim label inside the namespace is used" {
  [ -z "$(claim_label_rejection 'assigned:my-bot')" ]
  [ "$(with_claim_label 'assigned:my-bot')" = "assigned:my-bot" ]
}

@test "a claim label outside the assigned: namespace is rejected" {
  # The failure this prevents is silent in both directions — this plugin's claims
  # stop being visible to other claimants, and theirs stop being visible here.
  [ -n "$(claim_label_rejection 'in-progress')" ]
  [ -n "$(claim_label_rejection 'claimed:agent')" ]
  [ "$(with_claim_label 'in-progress')" = "assigned:agent-session" ]
}

@test "the bare namespace is rejected, not accepted as a prefix match" {
  # `assigned:` passes a naive prefix test while naming no claimant at all, which
  # is why the case checks it before the prefix pattern rather than after.
  [ -n "$(claim_label_rejection 'assigned:')" ]
  [ "$(with_claim_label 'assigned:')" = "assigned:agent-session" ]
}

@test "a label that merely contains the namespace is rejected" {
  # The requirement is a prefix. `not-assigned:x` contains the string and is a
  # different namespace entirely.
  [ -n "$(claim_label_rejection 'not-assigned:x')" ]
  [ "$(with_claim_label 'not-assigned:x')" = "assigned:agent-session" ]
}

@test "rejection reasons name what is wrong, not just that something is" {
  # These strings are rendered into the session-start note verbatim, and a note
  # saying a value was ignored without saying why leaves the operator guessing at
  # the fix.
  [[ "$(worktree_path_rejection '/tmp/wt')" == *"absolute"* ]]
  [[ "$(worktree_path_rejection '../wt')" == *".."* ]]
  [[ "$(claim_label_rejection 'in-progress')" == *"assigned:"* ]]
}
