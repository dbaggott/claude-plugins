#!/usr/bin/env bash
#
# Measures whether a passage of skill prose is load-bearing: runs one eval case
# against two trees that differ in that passage, and prints both scores and
# the delta. Nothing here gates. The exit status says whether both arms ran,
# never which won; near-equal scores at the default 8 runs mean "not separable
# at this n", not "equal", and about 30 runs separate arms that land close.
#
# Usage:
#   scripts/dev/prose-ab.sh --case <name> [--plugin <name>] [--runs <n>]
#                           [--model <model>] [-j <n>] <head>
#
# The base arm is the repository you run it from. <head> is either a second
# repository root (a worktree) or a patch file, which is applied to a temporary
# copy of the base's working tree; it is `git diff` output taken at the
# repository root, and a hunk that fails to apply fails the run. The copy
# carries the base's uncommitted edits, so a patch of those same edits does not
# apply to it: stash them, or diff from another worktree. The case is
# <plugin>/evals/<name>/, found one level below the head root, and the base arm
# is the plugin of the same name under the base root with the head's case
# copied in, so a case that exists only in the head still runs against the
# base. Each arm runs from a temporary copy of its plugin, which keeps
# `evals/results/` out of either checkout, and is passed to `claude plugin
# eval` as an absolute path: a bare directory name such as `dnbg-workflow`
# resolves to the *installed* plugin of that name, not the directory.
#
# Each run is a `claude -p` session on your own credential: the seed cases
# under dnbg-workflow/evals/ cost roughly $0.03 to $0.10 and 10 to 60 seconds
# apiece, so a two-arm measurement at 8 runs is in the order of a dollar.
#
# Examples, against the seed cases:
#   scripts/dev/prose-ab.sh --case rules-reach-session --runs 1 .
#       The canary: a 0 means the plugin's hooks did not reach the run in this
#       environment, which makes every other case's result ambiguous.
#   git diff > /tmp/trim.patch
#   scripts/dev/prose-ab.sh --case routing /tmp/trim.patch
#       Whether a trim of the pickup prose changes which skill loads first. A 0
#       on `routing` is read against the runs' `error` field (a turn cap or a
#       timeout, counted in the `errors=` column) before it is read as a
#       routing failure.
#   scripts/dev/prose-ab.sh --case full-url ../other-worktree
#
# What a case can measure here: a prompt the passage decides. A plain prompt
# that the model gets right without the passage ("resolve #110") scores the
# same in both arms and measures nothing. Nothing that needs an authenticated
# `gh` or a dispatched subagent runs under the eval runner; those stay under
# tests/evals/. The next case worth writing is the non-GitHub decline, a repo
# whose origin is a gitlab.com URL, which is the first to need `--scaffold`.
#
# Output, last:
#   base: score=<0..1> errors=<n>/<runs> status=<n> json=<path>
#   head: score=<0..1> errors=<n>/<runs> status=<n> json=<path>
#   delta=<head minus base>
# Exits 0 when both arms ran to a score, 1 on a usage error, 2 when an arm did
# not. The JSON files are the runner's full result documents and are kept.

set -uo pipefail

usage() {
  sed -n '/^# Usage:/,/^#$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 1
}
die() { echo "prose-ab.sh: $*" >&2; exit "${2:-1}"; }

case_name='' plugin='' head='' runs=8
model=() jobs=()
while [ $# -gt 0 ]; do
  case "$1" in
    --case)   [ $# -ge 2 ] || usage; case_name=$2; shift 2 ;;
    --plugin) [ $# -ge 2 ] || usage; plugin=$2; shift 2 ;;
    --runs)   [ $# -ge 2 ] || usage; runs=$2; shift 2 ;;
    --model)  [ $# -ge 2 ] || usage; model=(--model "$2"); shift 2 ;;
    -j)       [ $# -ge 2 ] || usage; jobs=(-j "$2"); shift 2 ;;
    -h|--help) usage ;;
    -*) die "unknown option $1" ;;
    *)  [ -z "$head" ] || usage; head=$1; shift ;;
  esac
done
[ -n "$case_name" ] && [ -n "$head" ] || usage
[[ "$runs" =~ ^[1-9][0-9]*$ ]] || die "--runs takes a positive integer, got '$runs'"
[ -e "$head" ] || die "head '$head' does not exist"

base_root=$(git rev-parse --show-toplevel) || die "not inside a git repository"
tmp=${TMPDIR:-/tmp}
work=$(mktemp -d "${tmp%/}/prose-ab.XXXXXX") || exit 1
trap 'rm -rf "$work/base" "$work/head" "$work/root"' EXIT

if [ -d "$head" ]; then
  head_root=$(cd "$head" && pwd)
else
  # The copy is the base's working tree, modifications included, so the patch
  # lands on what the operator is looking at rather than on HEAD. `git apply`
  # works outside a repository, so the copy needs no `.git`.
  patch=$(cd "$(dirname "$head")" && pwd)/$(basename "$head")
  head_root=$work/root
  mkdir "$head_root"
  git -C "$base_root" ls-files -z \
    | while IFS= read -r -d '' f; do [ -e "$base_root/$f" ] && printf '%s\0' "$f"; done \
    | tar -C "$base_root" --null -T - -cf - | tar -C "$head_root" -xf - \
    || die "copying $base_root failed"
  (cd "$head_root" && git apply "$patch") || die "patch $head did not apply cleanly"
fi

# The case names the plugin: `<plugin>/evals/<case>/` one level below the head
# root, with --plugin deciding only when more than one plugin has it.
found=()
for d in "$head_root"/*/evals/"$case_name"/; do
  [ -d "$d" ] || continue
  d=${d%/evals/*}
  found+=("${d##*/}")
done
if [ -n "$plugin" ]; then
  [ -d "$head_root/$plugin/evals/$case_name" ] \
    || die "no case $case_name under $head_root/$plugin/evals/"
else
  case ${#found[@]} in
    0) die "no */evals/$case_name/ one level below $head_root" ;;
    1) plugin=${found[0]} ;;
    *) die "case $case_name is in several plugins under $head_root: ${found[*]}; pick one with --plugin" ;;
  esac
fi
[ -d "$base_root/$plugin" ] || die "base $base_root has no plugin $plugin"

if [ -n "${patch:-}" ]; then
  outside=$(git apply --numstat "$patch" | cut -f3- | grep -v "^$plugin/" || true)
  [ -z "$outside" ] \
    || echo "notice: hunks outside $plugin/ applied and change nothing in the arm: $(echo "$outside" | tr '\n' ' ')"
fi

copy_plugin() {  # <from root> <to>
  cp -R "$1/$plugin" "$2" && rm -rf "$2/evals/results"
}
copy_plugin "$base_root" "$work/base" || die "copying $base_root/$plugin failed"
copy_plugin "$head_root" "$work/head" || die "copying $head_root/$plugin failed"
rm -rf "$work/base/evals/$case_name"
mkdir -p "$work/base/evals"
cp -R "$head_root/$plugin/evals/$case_name" "$work/base/evals/" || die "copying the case failed"

run_arm() {  # <arm>
  echo "running $1 arm: $runs runs of $case_name from $work/$1 (quiet under --json)"
  claude plugin eval "$work/$1" --case "$case_name" --ablation none --runs "$runs" \
    ${model[@]+"${model[@]}"} ${jobs[@]+"${jobs[@]}"} \
    --threshold 0 --no-publish --trust-plugin --json "$work/$1.json"
}
run_arm base; base_status=$?
run_arm head; head_status=$?

# A score that reads `null` means the runner wrote no case result at all.
read_arm() {  # <arm>
  jq -r --arg c "$case_name" '
    .cases[] | select(.name == $c)
    | "score=\(.aggregates.score) errors=\([.arms.with[] | select(.error != null)] | length)"
  ' "$work/$1.json" 2>/dev/null
}
base_read=$(read_arm base); head_read=$(read_arm head)
echo "case=$case_name plugin=$plugin runs=$runs"
echo "base: ${base_read:-score=null errors=null}/$runs status=$base_status json=$work/base.json"
echo "head: ${head_read:-score=null errors=null}/$runs status=$head_status json=$work/head.json"
base_score=${base_read#score=}; base_score=${base_score%% *}
head_score=${head_read#score=}; head_score=${head_score%% *}
if [ "$base_status" = 0 ] && [ "$head_status" = 0 ] && [ -n "$base_read" ] && [ -n "$head_read" ]; then
  echo "delta=$(jq -n --argjson b "$base_score" --argjson h "$head_score" '$h - $b')"
  exit 0
fi
echo "delta=null"
exit 2
