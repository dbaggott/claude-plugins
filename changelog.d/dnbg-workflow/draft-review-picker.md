Asking `reviewer` to review a draft PR now stops and asks, instead of noting the
draft status and reviewing anyway. It offers **"Review it now"** (recommended —
the old behavior) or **"Wait until it's ready"**, which arms the existing
`--was-draft` watch and reviews once the PR is marked ready.

The picker is skipped when you have already answered — "review it even though
it's a draft", "review it once it's ready". **In an unattended run** — a CI or
headless reviewer, the case `DNBG_REVIEWER_PRIVATE_KEY` exists for — nobody is
there to answer, so it takes the wait arm and reviews when the PR is marked
ready. A headless run that wants a verdict on a draft pre-answers the picker in
its prompt. Drafts *discovered* in issue mode are
unchanged: still held back without asking.
