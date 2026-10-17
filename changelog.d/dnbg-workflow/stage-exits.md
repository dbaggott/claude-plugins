Each stage of the project flow now ends by naming the next one. When a spec
review converges, a plain issue gets the `resolve` or `orchestrate` prompt to
paste; a tracking issue whose design review is `READY` gets an "Accept the
design?" question that writes the acceptance row and gives the `decompose`
prompt; and a decomposition or set review ends with the `orchestrate` prompt for
the parent. Each recommends running the next stage in a fresh session.

Asking to resolve a tracking issue that has no children yet no longer stops with
nothing offered: an accepted design gets a "Decompose it now" choice, and one not
yet accepted gets the design-review prompt.
