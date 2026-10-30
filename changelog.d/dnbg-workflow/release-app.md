Releases of these plugins are now published by a GitHub App dedicated to this
repository, `claude-plugins-dbaggott`, installed on it alone, in place of an App
shared with the owner's other repositories. A credential that leaks from another
repository can no longer publish a release here. The release workflow's own
actions are pinned to commit SHAs, so a moved tag cannot change what runs in the
job that holds the release credential.
