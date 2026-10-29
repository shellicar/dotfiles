#!/bin/sh
# First-save hold: a server up for less than the interval has nothing worth
# saving yet, whether or not it has ever saved.
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../../home/common/lib/tmux-snapshot.sh
. "$REPO/home/common/lib/tmux-snapshot.sh"

describe 'the sweep holds a server younger than the interval'

I=300 G=30 NOW=1000000000

# Up 50s: held.
sweep_should_save "$NOW" "$((NOW - 50))" '' "$I" "$G" && fail "saved a server up for 50s"
# Up 299s: still held, one second short of the hold.
sweep_should_save "$NOW" "$((NOW - 299))" '' "$I" "$G" && fail "saved a server one second short of the hold"
# Up exactly the interval: the hold is over, and with no prior save it is due.
sweep_should_save "$NOW" "$((NOW - 300))" '' "$I" "$G" || fail "held a server at exactly the interval"
