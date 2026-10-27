Decomposing a tracking issue now checks whether two children would rewrite the
same section of a file before marking them independent. A shared section gets a
dependency, moves into one child, or is split by sentence between the two
bodies, so two parallel PRs no longer give the same text conflicting meanings
and leave merge order to settle it. A file whose total size a test caps counts
as one section.
