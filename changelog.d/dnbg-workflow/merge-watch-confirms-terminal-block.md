Fixed the merge wait sometimes telling you a PR needed a human to unblock it when
it was seconds from mergeable. GitHub can briefly report a PR as blocked just
after its last check finishes; the merge wait now re-reads after a few seconds
before calling a block final, so it keeps waiting and catches the merge.
