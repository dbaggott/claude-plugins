`git-workflow`'s review-watch reference is now two files: arming and re-arming
the watch, read when a PR goes to review, and what each watch result means, read
when the watch returns. The reference had nearly reached the size an agent can
read in one call, past which the read is cut off mid-file. The results file
says which results the merge-stage instructions handle differently.
