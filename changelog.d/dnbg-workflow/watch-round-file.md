A review watch that wakes on a new review, comment or push now fetches the
review round itself and names the file it wrote it to, so the agent reads the
round on the turn it wakes instead of spending a turn fetching it. If that
fetch fails, the watch prints the command to run, as before.
