An author working with no operator to ask, as under `orchestrate`, that finds
mid-implementation that the issue's design has to change now asks before
building the change, as a `Delegated question:` on the issue, instead of
building it and noting it in the PR description or beside its send-to-review
question. `orchestrate` triages a departure an author reports as already made
the way it triages a question, and answers it before dispatching the reviewer.

The delegated-mode eval gains a `departure` fixture that checks for exactly
this: `FIXTURE=departure tests/evals/delegated-mode/run.sh`.
