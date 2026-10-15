Fixed the issue body diff failing on an issue with a long edit history, which
is the usual state of a tracking issue. `issue-reviewer` and `orchestrate`
got an error and no diff once the past bodies outgrew the system's limit on
command arguments; they now get the diff like on any other issue.
