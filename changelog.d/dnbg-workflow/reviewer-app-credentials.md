**The reviewer bot now needs the `contents: write` permission.** Without it a
review posts and reads correctly but counts for nothing: GitHub does not let it
move `reviewDecision`, so on a repo that requires an approval the bot can never
satisfy the gate, and it cannot resolve its own review threads either. Nothing
reports this — the review simply has no effect.

**If you set up your reviewer before this release, you have to grant it by
hand.** A GitHub App's permissions are fixed when it is created, so re-running
the setup will not change an existing one. Add *Contents: Read and write* at
`https://github.com/settings/apps/<your-app>/permissions`, then accept the
pending request on each installation — the grant does nothing until you do.
`reviewer-setup`'s **Repair / rotate** section has the steps.

**Minting a bot token now checks the permissions it was granted** and tells you
what is missing, why it matters, and how to fix it. It is silent when nothing is
missing, and it does not mind an App that holds extra permissions for other
purposes.
