#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"

describe "ff started at / still prunes Claude worktrees"

# Searching the real / is too slow and reaches outside the test, so find is
# replaced by one that records its arguments, one per line, and the patterns ff
# built are checked against what find prints for entries under /: /x, not //x.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/find" <<'SHIM'
#!/bin/sh
printf '%s\n' "$@" > "$FIND_ARGS"
SHIM
chmod +x "$WORK/bin/find"

FIND_ARGS=$WORK/find.args
export FIND_ARGS
(cd / && PATH=$WORK/bin:$PATH HOME=$WORK/home "$REPO/home/common/bin/ff" -name '*.py')

args=$(cat "$FIND_ARGS")
assert_contains "$args" "$NL/.claude/worktrees$NL"
assert_contains "$args" "$NL/*/.claude/worktrees$NL"
