Tightened the `reviewer` skill's verification discipline, so a review is less
likely to publish a finding that isn't real or approve something it never
checked. Reviews now read PR content at the head SHA rather than a local branch
ref, derive a local changed set against the merge-base, read whole files when the
criterion is that something is *absent*, run probes under the target's real shell
and working directory, and re-list before retrying a review POST that 5xx'd.
Mechanical gates (a required changelog fragment, a JSON parse, a formatter) are
left to CI, and a generated artifact (a GIF, a snapshot, a lockfile) is
render-verified once rather than every round — with the reviewer's judgment spent
on whether what those gates accepted is accurate. Two techniques added: sweeping
a feature's identifier families before reading the diff, and computing countable
properties instead of eyeballing them.
