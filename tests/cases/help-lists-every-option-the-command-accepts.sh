#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"

describe "help lists every option the command accepts"

# The help is a slice of the header comment, so an option added to the parser
# and not to the comment is accepted and undocumented, and a slice that drifts
# from the comment silently drops the tail.

for cmd in git-refresh git-cleanup; do
  help=$("$REPO/home/common/bin/$cmd" --help 2>&1)
  accepted=$(sed -n '/^ *case "\$arg" in/,/^ *esac/p;/^ *case "\$1" in/,/^ *esac/p' \
    "$REPO/home/common/bin/$cmd" |
    sed -n 's/^ *\(-[^)]*\)).*/\1/p' | tr '|' '\n' | grep '^-' | sort -u)

  for opt in $accepted; do
    case "$help" in
      *"$opt"*) ;;
      *) fail "$cmd --help does not mention $opt" ;;
    esac
  done
done
