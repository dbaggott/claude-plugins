#!/usr/bin/env bash
# The two jq programs that turn a PR's raw payloads into review activity, shared
# by the only two producers of it: watch-pr.sh, which already holds the payloads
# from the poll that woke it, and pr-round.sh, which fetches them. One definition
# so a caller reads the same objects whichever produced them.
#
# Both take `--arg s <since-iso> --arg slug <login-to-exclude>` and emit one
# compact object per line with `kind`, `author`, `at` and `body`. Feed
# ACTIVITY_JQ_REVIEWS the `gh pr view --json reviews,comments` payload and
# ACTIVITY_JQ_INLINE the `pulls/<n>/comments` one — inline findings appear in
# neither the other's source.
#
# `mine` matches both spellings GitHub uses for one bot: GraphQL reports a Bot
# author's login as `<slug>`, REST as `<slug>[bot]`.

# `$s` and `$slug` are jq variables bound by --arg, not shell ones.
# shellcheck disable=SC2016,SC2034  # sourced; the caller reads both.
ACTIVITY_JQ_REVIEWS='
  def mine: . == $slug or . == ($slug + "[bot]");
  (.reviews[]?  | select(.submittedAt > $s and (.author.login | mine | not))
    | {kind: "review", author: (.author.login // ""), state: (.state // ""),
       at: .submittedAt, body: (.body // "")}),
  (.comments[]? | select(.createdAt > $s and (.author.login | mine | not))
    | {kind: "comment", author: (.author.login // ""), at: .createdAt,
       body: (.body // "")})'

# `id` is emitted because replying in-thread needs it as `in_reply_to`; without
# it every reply costs a second fetch of what this payload already carries.
# shellcheck disable=SC2016,SC2034
ACTIVITY_JQ_INLINE='
  def mine: . == $slug or . == ($slug + "[bot]");
  .[] | select(.created_at > $s and (.user.login | mine | not))
  | {kind: "inline", author: (.user.login // ""), path: (.path // ""),
     line: (.line // .original_line), id: .id, at: .created_at,
     body: (.body // "")}'
