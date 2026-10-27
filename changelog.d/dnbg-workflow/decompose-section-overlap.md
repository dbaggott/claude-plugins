Decomposing a tracking issue now checks whether two children would rewrite the
same section of a file before leaving them independent. A shared section gets a
dependency, moves into one child, or is split by sentence between the two
bodies, so parallel children are told up front who owns the shared text instead
of finding out in review. A file near a size cap that a test enforces counts as
one section when both children add to it.
