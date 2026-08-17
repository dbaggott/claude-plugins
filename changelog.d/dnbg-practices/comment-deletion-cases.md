`coding-practices` now names more comment cases to delete: a comment confirming
what every competent reader already assumes, a warning about what breaks if the
code changes, and — the one that survives a standards pass today — such a warning
where a test already fails on the change it warns against. What stays in each
case is the property the code holds, stated positively; what goes is the argument
for the guard.

"Write the why, not the what" is reworded so it no longer reads as a ban on a
short statement of what a block is for.
