`git-workflow`'s self-review now says the code-review tool may finish in the
background, and that the PR waits for its result. A dispatched author that ends
its turn to wait says so, and `orchestrate` reads that as a wait instead of
prodding the author toward opening the PR early.

A diff of only generated or data files now skips the defect pass, with the skip
and its reason stated when the PR is announced and in its description. Size
alone does not qualify, and config a program acts on counts as logic.
