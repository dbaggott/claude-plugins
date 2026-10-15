A PR or issue watch now prints an `alive` line about once a minute while it
waits, so its background task output shows whether it is still running. Before,
a healthy watch and a dead one both left an empty output until the result line.
The result line and how to read it are unchanged.
