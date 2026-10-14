`orchestrate` now ends every run with retrospectives: the author, the reviewer
and the orchestrator each write a short local file on what slowed them down,
what a skill got wrong, what they worked around, and what they wished they could
have asked. They go under `~/.claude/dnbg-retrospectives/<owner>/<repo>/`; set
the new `retrospective_dir` option from `/plugin` to keep them elsewhere.

New `process-review` skill: say "review the retrospectives" and it reads a batch,
reports the patterns that recur with counts and quoted examples, and drafts
upstream issues for the ones the plugin is to blame for. Nothing is filed until
you approve the exact text.
