# For maintainers

```
.claude-plugin/marketplace.json   # the catalog
CHANGELOG.md                      # assembled at release time
changelog.d/<plugin>/             # pending fragments, one per PR
docs/                             # this directory: reference, read after deciding
dnbg-workflow/                    # the plugin
  .claude-plugin/plugin.json      # manifest, incl. the three userConfig knobs
  always-on-rules.md              # injected into every session
  hooks/                          # rule injection, two gates
  skills/                         # loaded on demand when the description matches
```

Changes go through a PR — never push to `main` directly.
[`CONTRIBUTING.md`](../CONTRIBUTING.md) covers the fragment rule, the scope of
what gets accepted, and how to run CI's checks locally.
[`releases.md`](releases.md) covers versioning and what triggers a release.

## Why the rules are injected twice

`inject-rules.sh` and `inject-rules-subagent.sh` print the same payload, because
**`SessionStart` output reaches the main loop and nothing else** — a subagent
spawned from that session receives none of it. Measured on Claude Code 2.1.226,
for the `general-purpose` and `Explore` agent types. That is why there are two
hooks rather than one, and why they share `rules-payload.sh`: a subagent working
to a different set of rules than its parent is the failure the split prevents.
The rules cost tokens on each subagent spawn as well as at session start, which
is the price of a subagent that has actually been told to work in a worktree.

## Where the version floor comes from

`docs/requirements.md` states v2.1.207 without deriving it. It is a floor taken
from the dated behaviors the plugin relies on, not a tested boundary: plugin
config reaches the hooks as `CLAUDE_PLUGIN_OPTION_*` environment variables,
which is the arrangement that settled at v2.1.207 when `${user_config.*}`
stopped substituting into shell-form fields, and `dnbg-all` resolves its
`dependencies`, which arrived at v2.1.143.

Both need re-deriving whenever the client moves under us, which is why they live
here rather than in front of a reader deciding whether to install.

## Where new content goes: skill vs always-on vs project CLAUDE.md

Three places content can live; default to the cheapest that fits.

| | Triggers | Cost |
| --- | --- | --- |
| **Skill** (`skills/<name>/SKILL.md`) | when the skill's `description:` matches the task | tokens only when loaded |
| **Always-on rule** (`always-on-rules.md`) | unconditionally, every session, every user | tokens on every session × every user |
| **Project `CLAUDE.md`** (in the consuming repo) | unconditionally, but scoped to that repo | tokens when working in that repo |

- Most guidance is procedural ("how to open a PR", "how we think about
  comments") and can be triggered by a description match — make it a skill.
- Only things that must apply to *every* response and can't be triggered by
  intent ("no flattery") justify always-on. That file is short on purpose.
- Facts about one repo — its layout, its build tool, its conventions — belong in
  that repo's `CLAUDE.md`, not here. The same goes for a stance that isn't
  universally true, which is why `velocity-tradeoff` is opt-in rather than a
  rule.

If you're tempted to add to `always-on-rules.md`, ask whether a skill
description could fire it instead. If yes, prefer the skill.

## If you forked this

Nothing in the plugin itself assumes this repo's setup — which repos it enforces
on is the `owners` config, and the skills read a repo's merge settings rather
than assuming them. The **CI** is a different matter, since a fork inherits
`.github/workflows/` verbatim:

- **`ci.yml`** works anywhere. It runs shellcheck and validates the JSON. Whether
  its `ci-required` umbrella actually *blocks* merges is your branch-protection
  setting, not something this repo can decide for you.
- **`release.yml`** needs a GitHub App, because a required status check
  and `GITHUB_TOKEN` are mutually exclusive here (see the comment at the top of
  that file). **It disables itself in a fork** — the job is guarded on an
  `AUTOMATION_APP_ID` variable you won't have, so it skips silently instead of
  failing on a missing credential. Versions stop auto-bumping and you can bump
  `plugin.json` by hand, or wire up your own App and set `AUTOMATION_APP_ID`
  (repository variable) plus `AUTOMATION_APP_PRIVATE_KEY` (repository secret).

If you don't want automated versioning at all, delete that workflow.

## Regenerating the README demos

Five GIFs, one script each, all driven by `render.sh`:

```bash
brew install asciinema agg
docs/media/render.sh           # all five
docs/media/render.sh gate      # or one, by name
```

Nothing else to set up: the demos build whatever state they drive, reach neither
the network nor any path outside `/tmp`, and an unrecognised name is an error
rather than a silent no-op.

`check-render.sh` fails CI when a committed artifact stops matching its script,
so the re-render is enforced rather than remembered — see below.

| Demo | What it is |
| --- | --- |
| `demo-gate` | A genuine capture — the real `check-worktree.sh` and real `git`, against a repo it builds. Reviews are formatted live from `fixtures/gate-reviews.json`, captured once from a real PR |
| `demo-resolve-review` | Reenacted. Two panes, resolver and reviewer, driven by an issue |
| `demo-vibe-review` | Reenacted. Two panes, no issue — conversation to PR to merge and cleanup |
| `demo-file-issue` | Reenacted, except the `BLOCKED` message, which the real hook produces at record time |
| `demo-work-summary` | Reenacted, condensed from a real 2026-08-11 session |

**Keep the reenactments honest.** They are scripted because the pickers and the
agent's own dialogue are Claude Code's interface and never reach stdout — not
because staging was more convenient. So each one must keep matching what the
skills specify: if a skill's flow changes, the demo depicting it is wrong and
needs re-scripting, not just re-rendering. The table above is the record of which
is which; keep it accurate as demos are added or reworked.

**The artifacts have four inputs and only one is the demo script.** `lib-demo.sh`
feeds every reenactment, and `demo-gate` and `demo-file-issue` print a hook's
real block message — so rewording one stales a GIF from a change that never
touches `docs/media/`. `docs/media/check-render.sh` is what catches that: for
each demo it re-runs the script and compares the output against the committed
`.cast`, and compares that `.cast`'s window size against `demos.sh`. It runs as a
step in `lint`, in under a second, because a no-op `sleep` first on `PATH`
removes the only thing in a demo that takes real time.

```bash
docs/media/check-render.sh     # what CI runs; same output locally
```

So the loop is: change a script, run `render.sh <name>`, commit the artifacts
with it. A demo missing from `demos.sh` fails the check rather than going
quietly unrendered.

Two things are deliberately outside it. The `.gif` is not compared — `agg` writes
it in the same `render.sh` call as the `.cast`, so a fresh `.cast` implies a
fresh `.gif` — and `demo-gate`'s repo path is compared with `/private/tmp`
normalised to `/tmp`, since macOS resolves that symlink and Linux does not.

**Keeping `demo-gate` reproducible is a constraint on editing it.** It builds its
own repo from pinned content and pinned commit dates, so its path and its commit
SHA are identical on every machine, and it draws reviews from a fixture rather
than the live API. Anything that puts wall-clock time, a live API read, the
recording machine's paths, or a terminfo-driven binary such as `clear` on screen
breaks the check for everyone else. That last one is not hypothetical: `clear`
emits the same three escapes in a different order on macOS and on
`ubuntu-latest`.

`lib-demo.sh` holds the shared renderer. The split-pane one is append-only
rather than repainting, because a full-screen repaint per step makes every GIF
frame a whole-screen change and the file several times larger.
