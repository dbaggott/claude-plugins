Fixed a set review that could never converge after a decomposition. Decomposing
a tracking issue could leave a late decision unapplied above the record of the
filed children, which the design review then flagged as a finding. Decomposing
now applies every pending decision, the design's acceptance included, before it
records the filing.
