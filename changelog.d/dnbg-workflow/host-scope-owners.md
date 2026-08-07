Only `github.com` remotes are covered by the enforcement hooks now. Previously
the owner match ignored the remote's host, so listing a GitHub org also gated a
same-named org on GitLab or Bitbucket — blocking edits there while every skill
instructed the agent to run `gh` commands that cannot work against that remote.

Also fixes a remote with an explicit port (`ssh://git@github.com:22/owner/repo`)
parsing the port as the owner, which made a covered repo read as uncovered and
silently lose its gate.

## Migration
If you left `owners` empty because you work on a non-GitHub host, you no longer
need to — set it to the GitHub accounts you want enforced and non-GitHub remotes
are ignored regardless. GitHub Enterprise hosts are *not* covered; that is
deliberate, since the skills' `gh` usage has not been verified against them.
