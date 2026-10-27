Fixed a reviewer's PR watch sleeping through a fix made only in the PR
description, such as corrected steps for an operator run. An edit to the
description by anyone other than the watcher now wakes the watch, and the round
packet carries the description as it stands, so the reviewer can check the fix
and resolve its thread without someone having to comment first.
