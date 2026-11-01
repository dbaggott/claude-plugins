A reviewer's PR watch no longer wakes it for a red build alone. The failing
checks now arrive as the `checks=` field on its next push, comment or review,
and a window with nothing else in it ends quietly. The author's watch still
wakes on a red build.

In issue mode, a reviewer no longer re-runs PR discovery after a PR watch
comes back idle. It still runs after every other return, and always when the
PR closes.
