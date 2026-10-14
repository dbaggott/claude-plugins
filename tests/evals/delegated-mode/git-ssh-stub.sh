#!/usr/bin/env bash
#
# GIT_SSH_COMMAND for an eval run: serves `git@github.com:<owner>/<repo>.git`
# from the bare repos under EVAL_REMOTES, so the fixture's origin reads as
# GitHub to a host check while fetch and push stay on this machine. Needs
# GIT_SSH_VARIANT=simple, which makes git pass only the host and the command.
#
# Kept to bash 3.2, the `bash` a stock macOS PATH resolves.

set -euo pipefail

: "${EVAL_REMOTES:?}"

[ "$#" -eq 2 ] || { echo "git-ssh-stub: expected <host> <command>, got: $*" >&2; exit 1; }
host=$1 cmd=$2

re="^git-(upload-pack|receive-pack) '([A-Za-z0-9._-]+/[A-Za-z0-9._-]+)'$"
if [ "$host" != git@github.com ] || ! [[ $cmd =~ $re ]]; then
  echo "git-ssh-stub: refusing $host $cmd" >&2
  exit 1
fi
service=${BASH_REMATCH[1]} path=${BASH_REMATCH[2]}
case "$path" in *..*) echo "git-ssh-stub: refusing $path" >&2; exit 1 ;; esac

[ -d "$EVAL_REMOTES/$path" ] || { echo "git-ssh-stub: no such repository: $path" >&2; exit 1; }
exec git "$service" "$EVAL_REMOTES/$path"
