An orchestrator running a tracking issue now appends decision-log rows and
friction-log bullets with one script call instead of fetching, hand-editing and
rewriting the whole parent body. The script confirms the write survived a
concurrent edit, retries when it didn't, never adds a line twice, and reports the
body's length for the archive threshold.
