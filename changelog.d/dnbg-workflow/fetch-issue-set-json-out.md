`fetch-issue-set.sh` takes `--json-out=<file>`: the set goes to the file, which
`jq` reads directly (its directory is created), and stdout carries only the
result line. On an error the
file is left empty, so it never holds an earlier run's set. The reviewer,
issue-reviewer and orchestrator recipes use it, so they no longer split the
object from the result line by hand.
