Fixed parallel agents in one session publishing each other's drafts. An agent
that went looking for its earlier PR description in the shared scratchpad could
find a sibling's draft and post it as its own.

Every agent the plugin dispatches now gets its own draft directory, named in its
prompt, and drafts its PR descriptions, issue bodies, comments and reviews there
under fixed names. A session nobody dispatched creates one at its first draft.
Before posting, an agent now recreates the directory if the scratchpad vanished
and refuses to post an empty body.
