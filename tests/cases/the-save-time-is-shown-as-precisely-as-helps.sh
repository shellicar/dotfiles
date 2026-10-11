#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-tmux.sh
. "$TESTS/fake-tmux.sh"

describe 'the status view shows the clock for today, the date this year, the year before that'

guard_path
# shellcheck source=../../home/common/lib/tmux-snapshot.sh
. "$REPO/home/common/lib/tmux-snapshot.sh"

assert_eq "$(when '2026-10-09 07:05' 2026-10-09)" 'today 07:05'
assert_eq "$(when '2026-07-01 23:59' 2026-10-09)" '1 Jul 23:59'
assert_eq "$(when '2025-12-25 10:00' 2026-10-09)" '25 Dec 2025'
assert_eq "$(when 'yesterday' 2026-10-09)" '?'
assert_eq "$(when '2026-13-01 10:00' 2026-10-09)" '?'
