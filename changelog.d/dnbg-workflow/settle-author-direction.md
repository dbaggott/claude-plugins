`git-workflow`'s review watch now settles for 10s instead of the script's 45s
default, so a review reaches you roughly half a minute sooner. The default is
sized to coalesce an author's burst of separate actions, which is what `reviewer`
watches; a reviewer files its verdict and inline comments in a single write, so
the author side was paying a coalescing window it had nothing to coalesce.
