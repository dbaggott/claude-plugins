`reviewer` no longer files style nits as inline comments. An inline comment is a
review thread, and a thread blocks the merge outright wherever
`required_conversation_resolution` is on — so a nit filed on a line held the
merge hostage while the review body called it non-blocking. The skill now tests
inline-vs-body on "would I hold the merge for it" rather than "does it request
action", forbids describing an open thread as non-blocking, and says to resolve a
nit-thread that turns out to be the last blocker.
