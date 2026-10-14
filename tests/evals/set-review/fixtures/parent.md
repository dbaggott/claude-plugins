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
- **C2. GitHub's `ubuntu-latest` runner image has a `C.UTF-8` locale.** Verified with `locale -a` in a workflow run.

## Requirements

- **R0.** A note is `notes/<slug>.md`: the line `# <title>`, one blank line, then the body to end of file. The repo carries a sample `notes/` of at least three notes in this format, one of whose bodies contains a double quote and a backslash.
- **R1.** `scripts/export.sh` writes every note to `export.json` as `{"notes": [{"slug", "title", "body"}]}`, ordered by slug compared bytewise.
- **R2.** `scripts/check-export.sh <file>` exits non-zero, naming the first offending note, when the file is not in R1's shape.
- **R3.** `scripts/import.sh <file> <dir>` writes an export's notes into `<dir>` in R0's format, refusing a `<dir>` that is not empty, so that exporting the imported notes reproduces the original export byte for byte.
- **R4.** Every script prints usage and exits 2 when called with the wrong number of arguments.

## Decisions

- **D1. JSON, not YAML, for the export.** Because: `jq` is already a dependency (C2) and nothing here parses YAML. Revisit if: a consumer needs comments in the file.
- **D2. Bytewise slug order, not creation order.** Because: it makes R3's byte-identical round trip possible without storing timestamps, and bytewise is the order both a `LC_ALL=C` glob and `jq`'s string comparison produce, so no two scripts can disagree on it. Revisit if: a consumer needs chronology.

## Open questions

- **Q1. Should the export include a schema version?** Default: no, because there is one consumer and one version; add it with the second.

## End-to-end acceptance criteria

- **A1.** On the sample `notes/`, `export.sh`, then `check-export.sh`, then `import.sh` into an empty directory, then `export.sh` over that directory produces a file identical to the first export. Contributes: R0, R1, R2, R3.

## Candidate decomposition

| # | Child | Covers | Depends on |
| --- | --- | --- | --- |
| [1]({{CHILD_EXPORT}}) | Export script | R0, R1 | — |
| [2]({{CHILD_CHECK}}) | Export checker | R2 | — |
| [3]({{CHILD_IMPORT}}) | Import script | R3 | 1 |

## Decision log

| Date | ID | Child | Entry | State |
| --- | --- | --- | --- | --- |
| {{DATE}} | D1, D2 | — | Initial decisions recorded with the design | decided |

## Friction log

Nothing yet.
