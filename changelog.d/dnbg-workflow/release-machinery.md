Plugin versions move to `YYYY.M.N` — year, unpadded month, Nth release of that
plugin that month. Each plugin now carries its own counter, and releases are
driven by changelog fragments rather than firing on every merge.

Releases are now tagged (`{plugin}--v{version}`) and published as GitHub
Releases with notes assembled from `changelog.d/`.

## Migration
The previous two-component scheme (`2026.4`) was not semver-parseable, which
meant no tag it produced could ever be selected by plugin dependency
resolution. Nothing is required of users. Anyone scripting against the old
two-component version should expect three components from now on.
