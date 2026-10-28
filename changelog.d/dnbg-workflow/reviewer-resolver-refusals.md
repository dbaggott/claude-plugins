Fixed the reviewer sending you to `reviewer-setup` when its bot is refused as
`shared-identity` (two roles configured with one App) or `no-login` (the App's
login is unknown), which setup does not fix. The reviewer skill now names each
of those with its own remedy: the bootstrap run for one role alone
(`--roles <role>`), or a `slug` in the role's `config.json`.
