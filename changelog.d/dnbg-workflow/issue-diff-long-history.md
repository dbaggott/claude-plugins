Fixed `issue-diff.sh` failing on an issue with a long edit history, which is
the usual state of a tracking issue. It printed `reason=issue-query-shape` and
no diff once one page of past bodies passed the system's argument-size limit;
it now diffs them like any other issue.
