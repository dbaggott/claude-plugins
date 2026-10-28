Fixed `orchestrate` stopping while its reviewer was still running. It stopped
on the reviewer's close-out for a PR, but an issue-mode reviewer keeps watching
the issue after each PR closes, and writes its retrospective only once no PR is
open and the issue is closed. So the orchestrator collected retrospectives
before the reviewer's existed, and a PR that joined the issue later was
reviewed with nobody listening.

The reviewer now ends its issue-mode assignment with its own report, opening
`**Reviewer close-out: assignment ended**`, and the orchestrator stops on that.
When the issue is still open after its last PR merged, the orchestrator asks
whether to close it; leaving it open tells the reviewer to end its assignment
anyway, and a session without `AskUserQuestion` leaves it open unless its
prompt says otherwise.
