Audited every `⚠️` marker in the repo against the emphasis budget, rather than
only the one file `watch-pr.sh` was rebalanced in. Roughly two thirds are gone,
and the files that had the most now carry a handful.

Each was judged on the stated test — does it mark a silent failure of the
reserved kind — with doubt resolved toward removing. That threshold retires a
whole category the earlier pass had kept: a marker whose own text reads "X is
load-bearing, not tidiness" is addressed to whoever might simplify the line, not
to anyone the line can hurt, however real the failure behind it.

What survives names a way the system goes wrong without saying so: a trimmed
exclusion entry failing open, an empty slug waking a watch on its own review, a
short SHA that can never match HEAD, an error body passing a shape gate and
blinding a whole window, a zero interval turning a watch into a busy loop around
`gh`, a foreground nap swallowing SIGTERM, a key reaching `openssl` through a
temp file, a hook anchor that un-gates every prefixed invocation, a discovery set
that is empty because a source died, and a test run writing into the developer's
real trace directory.
