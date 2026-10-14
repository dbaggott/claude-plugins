This is a **tracking issue** for a notes export: a script that writes the notes in this repo as JSON, a checker for that JSON, and an importer that reads it back.

## Problem

Notes live as Markdown files under `notes/`, one per note, with a title line and a body. Nothing can read them except a person. Moving them to another tool means copying each one by hand.

## Goals

- The notes can be exported to one JSON file and imported back without loss.
- A malformed export is caught before anyone imports it.

## Non-goals

- Syncing with any particular tool. The JSON is the interface; adapters are separate work.
- Attachments. Notes are text only.

## Constraints

- **C1. Notes are UTF-8 Markdown files named `<slug>.md`, first line `# <title>`.** Verified by listing `notes/` and reading each file's first line.
- **C2. `jq` 1.7 is available wherever these scripts run.** Verified with `jq --version` on the CI runner image and locally.

## Requirements

- **R1.** `scripts/export.sh` writes every note to `export.json` as `{"notes": [{"slug", "title", "body"}]}`, in slug order.
- **R2.** `scripts/check-export.sh <file>` exits non-zero, naming the first offending note, when the file is not in R1's shape.
- **R3.** `scripts/import.sh <file>` recreates `notes/` from an export, so that export, then import, then export again produces a byte-identical file.
- **R4.** Every script prints usage and exits 2 when called with the wrong number of arguments.

## Decisions

- **D1. JSON, not YAML, for the export.** Because: `jq` is already a dependency (C2) and nothing here parses YAML. Revisit if: a consumer needs comments in the file.
- **D2. Slug order, not creation order.** Because: it makes R3's byte-identical round trip possible without storing timestamps. Revisit if: a consumer needs chronology.

## Open questions

- **Q1. Should the export include a schema version?** Default: no, because there is one consumer and one version; add it with the second.

## End-to-end acceptance criteria

- **A1.** On a copy of `notes/`, `export.sh`, then `check-export.sh`, then `import.sh` into an empty directory, then `export.sh` again produces a file identical to the first export. Contributes: R1, R2, R3.

## Candidate decomposition

| # | Child | Covers | Depends on |
| --- | --- | --- | --- |
| [1]({{CHILD_EXPORT}}) | Export script | R1 | — |
| [2]({{CHILD_CHECK}}) | Export checker | R2 | — |
| [3]({{CHILD_IMPORT}}) | Import script | R3 | 1 |

## Decision log

| Date | ID | Child | Entry | State |
| --- | --- | --- | --- | --- |
| {{DATE}} | D1, D2 | — | Initial decisions recorded with the design | decided |
| {{DATE}} | — | — | Design accepted: spec review READY, operator sign-off in session | decided |

## Friction log

Nothing yet.
