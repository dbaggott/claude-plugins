`git-workflow` adds a step between making changes and opening the PR: re-read
your own diff against the standards you loaded, with those files re-opened rather
than recalled, and grep the diff for anything a standard states as countable. Fix
what you find before pushing.

The numbered steps after it shift by one. Three references that pointed at
"step 7" now name what they mean instead, so a later insertion can't silently
falsify them.
