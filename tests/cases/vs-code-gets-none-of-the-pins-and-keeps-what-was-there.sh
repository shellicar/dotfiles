#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "VS Code gets none of the pins and keeps what was there"

commit A
commit B A
ref_set refs/heads/main A
ref_set refs/heads/feature/x B

# Whatever the environment running the suite carries is cleared, so the case
# states both starting points itself.
for v in $(env | sed -n 's/^\(GIT_CONFIG_[A-Z0-9_]*\)=.*/\1/p'); do unset "$v"; done

SEEN=$WORK/seen
opener() { env | grep '^GIT_CONFIG_' | sort > "$SEEN"; }
REVIEW_OPENER=opener

# Each starting point sources the library in its own shell, since sourcing is
# what pins. With an argument, one entry is already in the environment first.
review_sees() (
  before=0
  if [ -n "${1:-}" ]; then
    export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0="$1"
    before=1
  fi
  guard_path
  # shellcheck source=../../home/common/lib/git-common.sh
  . "$REPO/home/common/lib/git-common.sh"
  review_folder() { printf '/repo'; }
  [ "${GIT_CONFIG_COUNT:-0}" -gt "$before" ] || fail 'sourcing the library pinned nothing'
  pinned=$GIT_CONFIG_COUNT
  review_main feature/x main || fail 'review_main failed'
  # The command itself is still pinned after the opener has run.
  [ "$GIT_CONFIG_COUNT" = "$pinned" ] || fail 'the pins were lost from the command itself'
  cat "$SEEN"
)

# An entry already there before the command started reaches VS Code untouched.
assert_eq "$(review_sees /somewhere)" 'GIT_CONFIG_COUNT=1
GIT_CONFIG_KEY_0=safe.directory
GIT_CONFIG_VALUE_0=/somewhere'

# With nothing there before, VS Code sees no GIT_CONFIG_ variable at all.
assert_eq "$(review_sees)" ''
