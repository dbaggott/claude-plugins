Fixed two ways a role App's credentials could be read back. The short-lived
token used to sign in as an App no longer appears in the process list while it
is being exchanged, where any user on the machine could read it, and a failing
private key command is no longer echoed into the session's output, where a
vault token passed as one of its arguments would have been logged.

Setting up pushes as the author now refuses, by name, a plugin path containing
`"`, `$`, a backtick, a backslash or a newline, which the push would otherwise
have run through the shell.
