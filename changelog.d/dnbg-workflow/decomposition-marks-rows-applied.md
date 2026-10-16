Decomposing a tracking issue now marks the decision-log rows the spec review
and the acceptance produced `applied` when it files the children, and a set
review response that applies a row marks it the same way. Before, those rows
reached `orchestrate` at `decided`, where each one read as a design change
still to sweep across every child. `orchestrate` also no longer sweeps a row
the body and children already carry: it marks the row `applied` and says so
in one comment on the parent. The set review flags a parent whose filing left
a row at `decided`.
