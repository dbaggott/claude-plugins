`coding-practices` and `work-summary` have moved out into their own plugins,
`dnbg-practices` and `dnbg-work-summary`. This plugin now carries the GitHub
workflow: `git-workflow`, `issue-workflow`, `velocity-tradeoff`, `reviewer` and
`reviewer-setup`, plus the two enforcement hooks.

`prototype-velocity` is renamed `velocity-tradeoff`. The old name described a
project stage; the skill's own framing is that the trade is a ratio — blast
radius, reversibility, time-to-notice, test coverage, users — and not a fact
about the project.

## Migration
**Any repo whose `CLAUDE.md` opts in must change `dnbg-workflow:prototype-velocity`
to `dnbg-workflow:velocity-tradeoff`.** The old name does not error; it silently
stops loading, so the opt-in simply stops taking effect.

If you want `coding-practices` or `work-summary`, install them:

    /plugin install dnbg-practices@dnbg
    /plugin install dnbg-work-summary@dnbg

or `/plugin install dnbg-all@dnbg` for everything. This plugin does **not**
depend on them — the workflow skills stand alone, and their few references to
coding standards are optional pointers rather than requirements.
