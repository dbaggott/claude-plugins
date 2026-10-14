#!/usr/bin/env bash
# Sourced by the evals that file fixture issues.

# <file> <KEY=value>... -> the fixture with each {{KEY}} replaced by its value,
# taken literally
render() {
  local f="$1" out kv; shift
  out=$(cat "$f")
  for kv in "$@"; do out=${out//"{{${kv%%=*}}}"/"${kv#*=}"}; done
  printf '%s\n' "$out"
}
