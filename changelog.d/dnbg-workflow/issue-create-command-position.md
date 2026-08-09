**The issue-creation gate no longer blocks commands that merely talk about
creating an issue.**

It decided what a command did by grepping the whole command string, so the phrase
matched wherever it appeared — including inside a quoted argument or a heredoc
body, where it is text rather than a command. Any command whose payload discussed
issue creation was blocked, and the payloads most likely to do that are the ones
written while working on this repo: review bodies, commit messages, issue text. It
blocked a reviewer bot from posting a review *about this hook*.

The gate now requires the phrase to be in command position — the start of a line,
or after `;`, `&&`, `||`, `|` or `(` — and masks quoted spans first. Genuine
invocations are unaffected, including ones that follow another command.

Heredocs are why command position is the load-bearing half: a heredoc body is not
quoted, so masking alone would have left the commonest case still blocked.

One accepted limitation: a heredoc line that *begins* with the phrase still
matches. A false negative only means a skill went unloaded, which the workflow's
own claim check largely covers; a false positive blocks real work and points you
at a skill irrelevant to it.
