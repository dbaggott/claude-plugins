Fixed the reviewer sending you to `reviewer-setup` when its bot is refused as
`shared-identity` (two roles configured with one App) or `no-login` (the App's
login is unknown), which a plain setup run skips. The reviewer skill now gives
each its own remedy: setup for one role alone (`--roles <role>`), or the App's
`slug` set beside the role's other settings. It also says that the `--login`
call reports a refusal on stdout with exit 0, and to stop and report any reason
it does not list.
