The PR watch no longer reports a failing check from a superseded workflow run.
When a second run starts on the same commit (marking a PR ready does this), the
first run's checks stay on the commit. The watch used to read them, so it could
name a check that was green or still running in the live run, and list one name
twice. It now reads only the newest run of each check. A cancelled check is no
longer counted as a failure.
