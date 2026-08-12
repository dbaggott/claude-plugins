Stopped assuming your repo has branch protection. Two rules were justified by a
merge gate the plugin cannot read and many repos do not have — on a repo with no
required checks, nothing is ever `BLOCKED` and a fully red build reports as
`UNSTABLE`, which `git-workflow` handed over as a plain "ready to merge".

- `git-workflow` now gives `UNSTABLE` its own arm in "Composing the merge
  command". You still get the merge command immediately, including while checks
  are running — non-passing checks are named alongside it, and a build that has
  already failed is no longer framed as ready to merge.
- `reviewer` keeps both of its CI rules (never hold a verdict for CI, never poll
  it) on reasoning that holds on any repo, instead of on branch protection
  catching red CI later.
- The posture behind both is stated once, in `reviewer`'s new "Repo settings you
  cannot read": an unreadable setting is assumed in whichever direction is safe,
  and no instruction rests on one being on.
