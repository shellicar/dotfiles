#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-tmux.sh
. "$TESTS/fake-tmux.sh"

describe 'the allowlisted launcher is found below a wrapper, and other scripts are not'

guard_path
# shellcheck source=../../home/common/lib/tmux-snapshot.sh
. "$REPO/home/common/lib/tmux-snapshot.sh"

# 100 is the pane's shell. Under it a node wrapper (200) running a script that
# is not allowlisted, and under that the launcher (300), with arguments. 400 is
# a sibling tree with an unrelated .mjs. 500 lists itself as its own child.
READER=fake
fake_command() {
  case $1 in
    100) echo '-zsh' ;;
    200) echo 'node /opt/tools/swe.mjs --flag' ;;
    300) echo 'node /home/me/bin/start-v2.mjs --session abc *' ;;
    400) echo 'node dev-server.mjs' ;;
    500) echo 'sh' ;;
  esac
}
fake_children() {
  case $1 in
    100) echo '200 400' ;;
    200) echo '300' ;;
    500) echo '500' ;;
  esac
}

assert_eq "$(detect_launcher 100)" start-v2.mjs
assert_eq "$(detect_launcher 200)" start-v2.mjs
assert_eq "$(detect_launcher 400)" ''
assert_eq "$(detect_launcher 500)" ''
