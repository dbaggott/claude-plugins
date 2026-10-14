This is a **tracking issue** for a scratch project filed by the restart eval, `tests/evals/restart/run.sh` in https://github.com/dbaggott/claude-plugins. The eval closes it when the run ends.

## Problem

`restart-eval/{{RUN}}/` does not exist. Two one-line files belong in it.

## Goals

- Both files exist on `main` with the contents the requirements give.

## Non-goals

- Any other change to the repo.

## Constraints

- **C1. Each child's PR adds only its own file under `restart-eval/{{RUN}}/`.** Several runs of the eval can be open at once, and the run directory is what keeps them apart.

## Requirements

- **R1.** `restart-eval/{{RUN}}/name.txt` holds the single line `restart eval`.
- **R2.** `restart-eval/{{RUN}}/greeting.txt` holds the single line `hello`.

## Decisions

- **D1. Plain text, one newline-terminated line per file.** Because: nothing reads these files but the eval. Revisit if: something else starts reading them.

## Open questions

None.

## End-to-end acceptance criteria

- **A1.** Both files are on `main` with the contents R1 and R2 give. Contributes: R1, R2.

## Candidate decomposition

| # | Child | Covers | Depends on |
| --- | --- | --- | --- |
| [1]({{CHILD_A}}) | Name file | R1 | — |
| [2]({{CHILD_B}}) | Greeting file | R2 | — |

## Decision log

| Date | ID | Child | Entry | State |
| --- | --- | --- | --- | --- |
| {{DATE}} | D1 | — | Initial decision recorded with the design | applied |

## Friction log

Nothing yet.
