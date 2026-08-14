`git-workflow` adds a step between committing and pushing: re-read your own diff
against the standards you loaded, with those files re-opened rather than
recalled, and grep the diff for anything a standard states as countable. Fix what
you find before pushing.

Committing and pushing were one step and are now two, so the diff exists to be
read. Steps after them renumber, and the references that pointed at "step 7" now
name what they mean instead, so a later insertion can't silently falsify them.
