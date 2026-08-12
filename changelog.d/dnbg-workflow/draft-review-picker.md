Asking you to review a draft PR now stops and asks. `reviewer` used to note the
draft status and review anyway, on the reasoning that you asked — but naming a
PR is not evidence you noticed it was still a draft, and the two readings lead to
opposite work. It now says the PR is a draft and offers a picker: **"Review it
now"** (recommended, the old behavior) or **"Wait until it's ready"**, which arms
the existing `--was-draft` watch and reviews when the PR is marked ready.

The picker does not fire when you have already answered — "review it even though
it's a draft", "review it once it's ready" — or on a PR that isn't a draft. With
no operator to ask (a headless run), it holds back and watches, since a verdict
and inline threads posted early can't be taken back.

Drafts *discovered* in issue mode are unchanged: they are still held back
without asking.
