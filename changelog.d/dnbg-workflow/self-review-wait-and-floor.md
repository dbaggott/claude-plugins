`git-workflow`'s self-review now says the code-review tool may finish in the
background, and that the PR waits for its result. A dispatched author that ends
its turn to wait says so in its report, so the orchestrator does not take the
turn as finished work.

A diff of only generated or data files now skips the defect pass, with the skip
and its reason stated in the PR description. Size alone does not qualify.
