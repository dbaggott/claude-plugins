# Issue workflow: labeling an issue

Part of the `issue-workflow` skill. Read this when filing an issue, from
`references/creating.md`, or when relabeling one.

Labels sort along independent axes; an issue carries one from each that applies, not one total:

- **Type** — what kind of work it is: `bug`, `enhancement`, `documentation`, etc. Apply exactly one. This is the axis a triager filters on first, so an unlabeled issue is effectively invisible to that pass.
- **Area** (`area:*`) — which subsystem it touches. The component axis that keeps a growing backlog scannable. Apply at least one; an issue genuinely spanning two subsystems gets both. The valid set is **per-repo and self-describing**: run `gh label list --repo <repo> --search area` and read each label's description — that listing is the catalog, not anything enumerated here, so it never goes stale against this skill. When none fits and the issue clearly belongs to a *recurring* subsystem, **propose** a new `area:<kebab>` label with a one-line description and get the operator's confirmation before creating it (`"<skill-dir>/../../scripts/as-role.sh" author <repo> -- gh label create <name> --repo <repo> --color <hex> --description "..."`, where `<skill-dir>` is this skill's Base directory). Don't mint area labels unilaterally — the per-repo set stays human-curated, and ad-hoc creation fragments the namespace (`area:db` vs `area:database`).

Two more axes are applied by other flows rather than here:

- **Claim** (`assigned:*`) — who is working it, applied by the claiming flow in `references/claiming.md`.
- **Project** (`project:<slug>`) — which tracking issue it belongs to, on the parent and every child. `references/decomposing.md` mints it and applies it when the children are filed. A child filed later carries it too, and its title takes the parent's `[<slug>]` tag. A plain issue carries none.
