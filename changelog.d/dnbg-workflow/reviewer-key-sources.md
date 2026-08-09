The reviewer bot's private key can now come from a secret manager or the
environment instead of a plaintext file, and its directory is hardened.

The key is resolved from the first source that yields one:

1. `DNBG_REVIEWER_PRIVATE_KEY` — the PEM itself.
2. `DNBG_REVIEWER_PRIVATE_KEY_COMMAND`, or `private_key_command` in
   `config.json` — a command whose stdout is the PEM.
3. `~/.config/dnbg/reviewer/private-key.pem` — the existing default, unchanged.

Route 2 is one hook that reaches every manager without this project integrating
with any of them (`op read`, `pass show`, `security find-generic-password -w`,
`secret-tool lookup`, `vault kv get`, `sops -d`). Route 1 stands alone: paired
with `DNBG_REVIEWER_APP_ID`, no config file or PEM needs to exist, which makes
running the reviewer in CI possible for the first time.

Three properties, each with a test:

- **The key command is read only from user config or the environment, never from
  a repository.** Nothing reads config from the working directory. This is what
  makes the hook safe — the command grants no capability someone who can already
  write `~/.config` lacked, and that argument fails the moment a cloned repo can
  supply the value.
- **The key is never written to disk on its way to `openssl`.** It is passed
  through a pipe rather than a temp file, so nothing can be stranded by a crash
  or an uncatchable signal.
- **A group- or world-writable config directory or key file is refused**, the way
  `ssh` refuses an over-permissive private key.

Behavior changes, effective as soon as the plugin updates:

- **`mint-token.sh` refuses to run against a loose config directory.** If yours
  is group- or world-writable it will now stop and tell you, rather than signing
  with whatever key it finds. Fix with `chmod go-w ~/.config/dnbg/reviewer`.
- **`bootstrap.py` sets the config directory to `0700`** on every run, including
  over an existing directory.

The plaintext file remains the default, and the README now says so explicitly —
with the reasoning — rather than leaving it as an unstated convention.
