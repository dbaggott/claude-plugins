The old `followup_dir` setting and the `~/.claude/dnbg-followups/` directory are no longer read. Last release kept both as fallbacks after the rename to `findings_dir` and `~/.claude/dnbg-findings/`.

If you set `followup_dir`, set `findings_dir` to the same path. If you still have open entries under `~/.claude/dnbg-followups/` or a custom follow-up directory, move them under your findings root, keeping the `<owner>/<repo>/` subdirectories. Otherwise `findings-review` and the closeout won't see them.
