Fixed a role's config directory being read differently by `reviewer-setup` and
by every later role call. Setup no longer takes `--config-dir`, which stored an
App where nothing else looked for it: set `DNBG_<ROLE>_CONFIG_DIR` instead, for
setup and every later call alike. A value of that variable in the `~alice/...`
form is now refused by both, and named at session start, rather than read as two
different directories.

`XDG_CONFIG_HOME`, which both already honoured, is now documented: when set, a
role's directory defaults to `$XDG_CONFIG_HOME/dnbg/<role>/`.

## Migration
A setup script passing `--config-dir <path>` to the `reviewer-setup` bootstrap
must export `DNBG_<ROLE>_CONFIG_DIR=<path>` instead; the flag is now an error.
