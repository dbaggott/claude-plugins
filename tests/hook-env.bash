# A controlled environment for the two rule-injection hooks. `load hook-env` in
# any suite that runs one, then call `hook_env_setup` from its `setup()`.
#
# SHARED RATHER THAN COPIED, for the same reason `tests/reap.bash` is: the
# rationale below is the expensive part, and a second copy drifts from the first
# silently — the two suites test hooks that must agree with each other, so a
# harness that quietly stopped matching would undercut exactly the property they
# exist to pin.
#
# A path carrying only the named binaries is the point of `stub_path`, and
# shadowing is not an alternative: the hooks ask `command -v`, which searches
# PATH for an executable, so the only way to make a binary absent is to build a
# PATH that genuinely lacks it.
#
# `bash`, `cat` and `dirname` are always included — the shebang's `env` resolves
# `bash` through PATH, the hooks emit their text with `cat`, and they locate the
# shared `lib.sh` with `dirname`. A missing one of those would fail a test for a
# reason unrelated to what it is checking. They are also not what the preflight
# is about: it reports on the binaries the *gates* need, and a machine without
# `dirname` has no working shell scripts at all, so there is nothing useful for a
# hook to say about it.
#
# `awk` is deliberately NOT in that set. It is not what either hook runs on, and
# adding it here would make its absence untestable.

hook_env_setup() {
  TMP="$(mktemp -d)"
  ROOT="$TMP/plugin"
  mkdir -p "$ROOT"
  RULES_TEXT='## Test rule
Always do the thing.'
  printf '%s\n' "$RULES_TEXT" > "$ROOT/always-on-rules.md"
}

teardown() { rm -rf "$TMP"; }

# The manifest `rules-payload.sh` reads the version stamp from. Deliberately NOT
# written by `hook_env_setup`: absent is the broken-install shape, so every suite
# that says nothing about the stamp exercises the silent-no-op path for free.
#
# ⚠️ Moving this into `hook_env_setup` would silently convert the two "the
# manifest is missing" tests in `inject-rules.bats` into tests of a manifest that
# is present, and each would still pass — the stamp is opt-in, so a run that
# never sets the option emits nothing either way. A test that cannot fail is
# worse than an absent one, because the coverage still reads as present.
#
# The stamp's gate is the option, so pair this with `run_hook_stamped_at` below:
# a manifest alone produces no stamp, and the option alone has no version to
# name.
write_manifest() {  # <version> [name]
  mkdir -p "$ROOT/.claude-plugin"
  printf '{"name":"%s","version":"%s"}\n' "${2-dnbg-workflow}" "$1" \
    > "$ROOT/.claude-plugin/plugin.json"
}

stub_path() {  # <bin>...
  STUB="$TMP/bin"
  rm -rf "$STUB"; mkdir -p "$STUB"
  local bin src
  for bin in bash cat dirname "$@"; do
    src="$(command -v "$bin")" || { echo "test setup: $bin not on PATH" >&2; return 1; }
    ln -sf "$src" "$STUB/$bin"
  done
}

# `env -i` is what makes the configured variant a separate helper rather than an
# exported variable: the stripped environment is the point of `run_hook`, so an
# option has to be handed in explicitly or it does not reach the hook at all.
# Named `_at` because each suite wraps these with its own `$HOOK` bound, so the
# call sites read `run_hook` with no path — the hook under test is a property of
# the suite, not of the call.
run_hook_at() {  # <hook> [plugin-root]
  run env -i PATH="$STUB" HOME="$TMP" CLAUDE_PLUGIN_ROOT="${2-$ROOT}" "$1"
}

run_hook_configured_at() {  # <hook> <worktree-path> <claim-label>
  run env -i PATH="$STUB" HOME="$TMP" CLAUDE_PLUGIN_ROOT="$ROOT" \
    CLAUDE_PLUGIN_OPTION_WORKTREE_PATH="$2" CLAUDE_PLUGIN_OPTION_CLAIM_LABEL="$3" "$1"
}

# The stamp is opt-in, so every test that expects one has to ask for it — which
# is the point of a separate helper rather than a value baked into `run_hook_at`.
# A default-on harness would leave the off-by-default behavior pinned by nothing,
# and that default is the whole feature: the stamp lands on artifacts other
# people read.
#
# Takes the option's value rather than hardcoding `true`, so the tests that pin
# what does *not* count as a yes go through the same path a real session does.
run_hook_stamped_at() {  # <hook> [option-value] [plugin-root]
  run env -i PATH="$STUB" HOME="$TMP" CLAUDE_PLUGIN_ROOT="${3-$ROOT}" \
    CLAUDE_PLUGIN_OPTION_VERSION_STAMP="${2-true}" "$1"
}
