#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "the fake refuses a rev-list --count form it does not model instead of answering 0"

# A form the fake cannot read must fail rather than answer 0, which would read
# as a real distance. Each form here is one the fake does not model: a single
# rev, a flag before the ^ form, and the ^ form with a third rev.
#
#   main   A - M
commit A
commit M A
ref_set refs/heads/main M

refused=''
for form in "rev-list --count main" \
            "rev-list --count --first-parent ^main" \
            "rev-list --count main ^A ^M"; do
  rm -f "$FAILED"
  # shellcheck disable=SC2086
  git $form >/dev/null 2>&1 && continue
  [ -f "$FAILED" ] && refused="$refused|$form"
done
# The refusals above are what this case asserts on, not failures of the case.
rm -f "$FAILED"

expected="|rev-list --count main|rev-list --count --first-parent ^main|rev-list --count main ^A ^M"
assert_eq "$refused" "$expected"
