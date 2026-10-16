A design review of a tracking issue now re-runs each constraint's verification
when the body states it as a single read-only command, such as a GitHub API read
or a search of the code, and blocks on a constraint whose result does not match
its claim. The round comment says which constraints were re-run and why the rest
were not.
