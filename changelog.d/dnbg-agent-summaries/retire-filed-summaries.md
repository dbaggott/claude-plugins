A summary filed as one or more issues is now marked `retired`, with a `Filed as
<URL>` line under its title naming every issue, instead of `superseded` by a
single issue URL. `superseded` now means only that a newer summary file replaces
it. A sweep that finds a summary still marked `superseded` by an issue URL
proposes the new form and writes the `Filed as` line for you.

The sweep no longer proposes a status for a file without one from words like
"SHIPPED" or "Filed as" wherever they appear in it. It reads what the file says
about itself, quotes the line its proposal rests on, and proposes `active` as
borderline when the file's own words conflict, so a file you still use is not
proposed for archive on a keyword deep in its body.
