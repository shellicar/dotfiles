#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"

describe "-b makes the named branch the trunk, named in full"

# Overriding the trunk must not reintroduce the short form. A repository with a
# local branch called origin/develop would otherwise answer for the trunk and
# every verdict would be about the wrong commit.

git_says() {
  case "$*" in
    "rev-parse --verify --quiet refs/remotes/origin/develop") echo develop-tip ;;
    *) fail "unexpected: git $*" ;;
  esac
}

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"

BASE_OVERRIDE=develop
resolve_main

expected="main=develop ref=refs/remotes/origin/develop"
actual="main=$MAIN ref=$MAIN_REF"
assert_eq "$actual" "$expected"
