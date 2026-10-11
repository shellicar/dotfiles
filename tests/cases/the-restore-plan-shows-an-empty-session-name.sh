#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-tmux.sh
. "$TESTS/fake-tmux.sh"

describe 'the dry run names a session called "" so it can be seen'

FAKE_SESSIONS=''
tmux_says() { fake_listing "$@" || [ $? -eq 1 ] || fail "unexpected: tmux $*"; }

guard_path
# shellcheck source=../../home/common/lib/tmux-snapshot.sh
. "$REPO/home/common/lib/tmux-snapshot.sh"

mkdir -p "$WORK/here"
panes=$(
  snap_pane '' 1 logs 0 "$WORK/here" start-v2.mjs
  snap_pane '' 1 logs 1 "$WORK/gone" start-v2.mjs
)
plan_for_server "$panes"
out=$(describe_plan "$panes")

assert_eq "$out" "create session: \"\"
create window: \"\":1 \"logs\" (2 panes)
    pane 0: cwd=$WORK/here
      run: start-v2.mjs
    pane 1: cwd=$WORK/gone (missing, opens in ~)
      skip start-v2.mjs: dir missing"
