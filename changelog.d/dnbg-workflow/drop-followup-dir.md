The old `followup_dir` setting and the `~/.claude/dnbg-followups/` directory are no longer read. 2026.10.65 kept both as fallbacks after the rename to `findings_dir` and `~/.claude/dnbg-findings/`.

## Migration
If you set `followup_dir`, set `findings_dir` to the same path. Move any open entries under `~/.claude/dnbg-followups/`, or under a custom follow-up directory, into your findings root, keeping the `<owner>/<repo>/` subdirectories. `findings-review` and the closeout no longer see entries left behind.
