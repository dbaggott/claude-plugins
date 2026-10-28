The PR reviewer now reports twice: a handoff when it approves, so its findings
reach you before you merge, and a close-out when the PR merges or closes, a
delta against that handoff. Each opens with a fixed first line, and an
orchestrated run relays the reviewer's handoff beneath the author's and waits
for the reviewer's close-out before it stops.

The reviewer now writes a findings entry for every finding it raised that is
still unaddressed at its approval, alongside the author's entry for one it
declined; `findings-review` and a tracking issue's closeout merge that pair as
one item.
