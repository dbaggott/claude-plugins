Picking up an issue, reviewing one, and handling review rounds and merges no
longer depend on reading a reference file the harness cuts off partway. The
longest ones were split into shorter files, each read whole at the step that
needs it, so an agent no longer acts on the first half of an instruction whose
second half it never saw.
