This is a **tracking issue** for a notes export: a script that writes the notes in this repo as JSON, a checker for that JSON, and an importer that reads it back.

## Problem

Notes are kept as Markdown files under `notes/`, one per note. Nothing can read them except a person, and moving them to another tool means copying each one by hand.

## Goals

- The notes can be exported to one JSON file and imported back without loss.
- A malformed export is caught before anyone imports it.

## Non-goals

- Syncing with any particular tool. The JSON is the interface; adapters are separate work.
- Attachments. Notes are text only.

## Constraints

- **C1. `jq` 1.7 is available wherever these scripts run.** Verified with `jq --version` on the CI runner image and locally.

## Requirements

- **R0.** A note is `notes/<slug>.md`: the line `# <title>`, one blank line, then the body to end of file. A slug matches `[a-z0-9][a-z0-9-]*`, and a title is one line. The repo carries a sample `notes/` in this format with at least three notes: two whose slugs are `a` and `a-b`, and one whose body contains a double quote and a backslash.
- **R1.** `scripts/export.sh [dir] [out]` writes every note in `dir` (default `notes/`) to `out` (default `export.json` in the current working directory) as `{"notes": [{"slug", "title", "body"}]}`, ordered by slug compared bytewise.
- **R2.** `scripts/check-export.sh <file>` exits non-zero, naming the first offending note, when the file is not in R1's shape or a note's slug or title is not in R0's form.
- **R3.** `scripts/import.sh <file> <dir>` writes an export's notes into `<dir>` in R0's format, refusing a `<dir>` that is not empty and, before writing anything, a file with a slug or title not in R0's form, so that exporting the imported notes reproduces the original export byte for byte.
- **R4.** Every script prints usage and exits 2 when called with the wrong number of arguments.
- **R5.** `scripts/import.sh` runs `scripts/check-export.sh` on `<file>` before writing anything, and refuses the file, writing nothing, when the check fails.

## Decisions

- **D1. JSON, not YAML, for the export.** Because: `jq` is already a dependency (C1) and nothing here parses YAML. Revisit if: a consumer needs comments in the file.
- **D2. Bytewise slug order, not creation order, set by sorting on `.slug` in `jq`.** Because: it makes R3's byte-identical round trip possible without storing timestamps, and `jq` compares strings bytewise, so the export and the checker share one comparison. A file listing is not used for the order, since the `.md` suffix takes part in it and lists `a-b.md` before `a.md`. Revisit if: a consumer needs chronology.

## Open questions

- **Q1. Should the export include a schema version?** Default: no, because there is one consumer and one version; add it with the second.

## End-to-end acceptance criteria

- **A1.** On the sample `notes/`, `export.sh`, then `check-export.sh`, then `import.sh` into an empty directory, then `export.sh` over that directory produces a file identical to the first export. Contributes: R0, R1, R2, R3. Recorded by: the closeout PR's author, who runs it on the PR before the project review. Re-run if anything under `scripts/` or `notes/` changes.

## Candidate decomposition

| # | Child | Covers | Depends on |
| --- | --- | --- | --- |
| [1]({{CHILD_EXPORT}}) | Export script | R0, R1 | — |
| [2]({{CHILD_CHECK}}) | Export checker | R2 | — |
| [3]({{CHILD_IMPORT}}) | Import script | R3, R5 | 1 |

## Decision log

| Date | ID | Child | Entry | State |
| --- | --- | --- | --- | --- |
| {{DATE}} | D1, D2 | — | Initial decisions recorded with the design | applied |
| {{DATE}} | — | [1]({{CHILD_EXPORT}}), [2]({{CHILD_CHECK}}), [3]({{CHILD_IMPORT}}) | Children filed from the candidate decomposition | applied |

## Friction log

Nothing yet.
