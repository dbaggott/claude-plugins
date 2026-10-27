A design review of a tracking issue now checks that each child in the candidate
decomposition can meet the requirements it covers when it merges: the code each
one needs ships in that child or in one it depends on. It also checks that a
requirement moving a write to a different role is covered by the child that owns
the place the write happens. Either failure is a blocking finding on the parent,
caught before the children are filed rather than during decomposition.
