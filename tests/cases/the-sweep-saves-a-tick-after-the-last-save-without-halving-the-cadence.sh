#!/bin/sh
# Throttle with grace: two ticks one interval apart each save. A save takes a few
# seconds and the timer jitters, so a tick one interval after the last save sees
# now - last a hair under the interval. The grace (now - last >= interval - grace)
# lets that still save; without it the gate would want >= interval, skip the
# tick, and halve the cadence. A save much newer than that is still throttled.
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../../home/common/lib/tmux-snapshot.sh
. "$REPO/home/common/lib/tmux-snapshot.sh"

describe 'the sweep saves a tick after the last save without halving the cadence'

I=300 G=30 NOW=1000000000
UP=$((NOW - 100000)) # long past the first-save hold

# a save 200s ago is too recent: throttled.
sweep_should_save "$NOW" "$UP" "$((NOW - 200))" "$I" "$G" && fail "saved a server whose last save was 200s ago"
# one second inside the throttle (269s): still skipped.
sweep_should_save "$NOW" "$UP" "$((NOW - 269))" "$I" "$G" && fail "saved one second inside the throttle"
# a save 270s ago (exactly interval - grace) is the boundary: due.
sweep_should_save "$NOW" "$UP" "$((NOW - 270))" "$I" "$G" || fail "skipped a save at exactly interval - grace"
# tick two, one interval after a save that took 5s: now - last = 295, under the
# interval but within the grace, so it saves (the cadence is not halved).
sweep_should_save "$NOW" "$UP" "$((NOW - 295))" "$I" "$G" || fail "skipped a tick one interval after the last save (cadence halved)"
