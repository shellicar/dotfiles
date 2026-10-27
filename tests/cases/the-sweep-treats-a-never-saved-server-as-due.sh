#!/bin/sh
# A server past the first-save hold with no @snapshot-last-save (never saved, or
# the value unreadable) is due: the throttle has nothing to measure against. An
# empty value and a non-numeric one both count as never-saved.
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../../home/common/lib/tmux-snapshot.sh
. "$REPO/home/common/lib/tmux-snapshot.sh"

describe 'the sweep treats a never-saved server as due'

I=300 G=30 NOW=1000000000
UP=$((NOW - 100000)) # long past the first-save hold

sweep_should_save "$NOW" "$UP" '' "$I" "$G" || fail "held a server that has never saved"
sweep_should_save "$NOW" "$UP" 'xyz' "$I" "$G" || fail "held a server whose last-save value is not a number"
