Fixed PR watches going blind on a pull request with a lot of review text. Once
the reviews and comments passed the operating system's argument-size limit
(128 KB for one body on Linux, 1 MB in total on macOS), every watch tick failed
with `reason=pr-view-shape` and the watch could no longer see the PR.
