A tracking issue now resolves the way a plain issue does. When its last child
closes, `orchestrate` authors the closeout PR itself: the as-built design doc,
the friction log's dispositions (still filed only after you approve their text),
and a recorded run for any end-to-end criterion no child ran. The PR carries
`Closes <tracking issue URL>`, and its merge closes the tracking issue.

The whole-project review now happens on that PR, as one review grading every
end-to-end criterion, instead of as a verdict comment on the tracking issue that
had to come back `ACCEPTED` before closeout could start. There is no longer a
"close out" command to give: an orchestrator restarted on a project whose
children are all closed picks up the closeout PR where its predecessor left it.
