# Releases, updating, and versioning

## Keeping up to date

**This plugin does not update itself.** Once installed it stays exactly as it is
until you update it — which is Claude Code's own default for a third-party
marketplace, and a deliberate one: automatically replacing code that already
runs on your machine is a decision worth making yourself.

**To keep up automatically**, turn on auto-update for this marketplace. Either
set it in `~/.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "dnbg": {
      "source": { "source": "github", "repo": "dbaggott/claude-plugins" },
      "autoUpdate": true
    }
  }
}
```

or toggle it in the UI — `/plugin` → **Marketplaces** → **dnbg** → **Enable
auto-update**. The two are the same setting: Claude Code reads the config field
and the panel reflects it.

The path matters. `extraKnownMarketplaces` is also valid in a project's
`.claude/settings.json`, where it prompts *every collaborator* to install the
marketplace — and that file is normally committed. Put this in your user file
unless you mean to ask a whole repo.

Either way, Claude Code checks after each session starts, with a random delay of
up to ten minutes, then refreshes the marketplace and updates installed plugins
on disk. Your running session keeps the version it launched with; you'll be
prompted to `/reload-plugins`, or the new version loads next launch.

> **Known gap — don't treat auto-update as sufficient yet.** That describes the
> intended behavior, and the *install* half is confirmed: given a marketplace
> that knows about a new version, a fresh session picked it up unaided in about
> two and a half minutes. The *refresh* half we have seen fail — the marketplace
> clone sat on one commit for 11½ hours across several fresh sessions and moved
> only under a manual update. The cause is not established. Until it is, run the
> by-hand update below when it matters, and check the disk rather than
> `/plugin`, which reports what the marketplace knows rather than what you have:
>
> ```
> ls -1 ~/.claude/plugins/cache/dnbg/dnbg-workflow/ | sort -V | tail -1
> ```

The config form also works in managed settings, so an administrator can enable
it for an organisation without asking each person to toggle it.

**To update once, by hand**, run these one at a time — submit each, wait, then
the next; pasting them together only registers the first:

```
/plugin marketplace update dnbg
```

```
/reload-plugins
```

The first refreshes the catalog **and** updates the installed plugins from this
marketplace — it reports how many it bumped, and says nothing about plugins when
there was nothing to bump. The second applies them to the running session.

To move a single plugin without refreshing the catalog, use
`/plugin update <plugin>@dnbg`. It reports *already at the latest version* when
there is nothing to do, so silence after a marketplace update usually means the
update already happened rather than that the command failed.

To stop plugin updates globally regardless of the above, set `DISABLE_AUTOUPDATER`.
To keep plugin updates while disabling Claude Code's own, set
`FORCE_AUTOUPDATE_PLUGINS=1` alongside it.

## Installing a specific version

Every release is tagged `{plugin}--v{version}` and published as a GitHub
Release, so a given version is addressable rather than implied. Which version
you end up on depends on whether marketplace auto-update is enabled for `dnbg`
in `/plugin` — with it on you track releases as they land, with it off you stay
on whatever you installed until you update deliberately.

## Versioning

Calendar versioning, `YYYY.M.N` — year, month, and the Nth release of *that
plugin* in that month. Each plugin carries its own counter, so releasing one
doesn't move the others. `.github/workflows/release.yml` computes it
after every merge to `main`, so authors never touch a version in a PR. Run
`claude plugin list` to see what you have installed.

Semver would be fictional here: the plugins ship rules and skills, not an API,
so there is no breaking change to anchor a major bump on. CalVer answers the
only question a consumer actually has — how fresh is this?

The third component is not a semantic, though. Claude Code resolves plugin
dependency version constraints against `{plugin}--v{version}` git tags, and
ignores any tag whose suffix doesn't parse as semver — so a two-component
`YYYY.N` tag would exist and never be selected. Semver also rejects leading
zeros in numeric identifiers, which is why the month is unpadded: `2026.8.1`,
never `2026.08.1`. That costs the columns lining up next to `2026.10.1`, and
nothing else; ordering is numeric and stays correct.

## What triggers a release

Changelog fragments. A plugin with pending fragments under
`changelog.d/<plugin>/` is released; a plugin without them is not — so a change
whose author forgot a fragment does not ship, and nothing breaks except that the
version doesn't move. [`CONTRIBUTING.md`](../CONTRIBUTING.md) covers writing
one, and [`changelog.d/README.md`](../changelog.d/README.md) covers the format.
