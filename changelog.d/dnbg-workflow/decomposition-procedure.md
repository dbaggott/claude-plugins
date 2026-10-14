`issue-workflow` can now decompose an accepted tracking issue into child issues.
It covers grouping requirements into children, the lines each child carries to
say what it covers and depends on, keeping every child's criteria runnable at its
own merge, and filing the children as GitHub sub-issues with blocked-by
relationships. Setting those relationships is safe to re-run after a partial
failure. It refuses to move an issue that already belongs to another parent.
