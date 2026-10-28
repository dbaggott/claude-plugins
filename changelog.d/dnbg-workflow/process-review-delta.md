`process-review` now saves each report under the retrospective root, in
`_reviews/`, and by default the next run reads only the retrospectives written
since the last full or delta run, plus the files behind its singletons. A
problem seen once in one run and again in a later one is now found as a
pattern, and a pattern already reported with no new evidence is not drafted
again. Name `all` to force a full read.
