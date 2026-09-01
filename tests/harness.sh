# Sourced by every case.
#
# There is no repository. A case says what git answers, calls the function under
# test, and asserts on what came back and on what git was asked to do. That
# second half is the only way to see a destructive step without performing one.
#
# git is a shell function here, so every caller in the sourced library gets it,
# including the ones that run in a subshell. The shim on PATH is the backstop:
# anything reaching for git in a child process, where a function cannot follow,
# hits a command that fails loudly instead of the real thing.

# A case can be run on its own, not only through run.sh.
[ -n "${WORK:-}" ] || WORK=$(mktemp -d)

TAB=$(printf '\t')
NL='
'

CASE_NAME=''
describe() { CASE_NAME=$1; }

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

# A file, not a variable: the code under test calls git inside subshells, and a
# variable set in one is lost when it exits.
GIT_LOG=$WORK/git.log
: > "$GIT_LOG"

git() {
  printf '%s\n' "$*" >> "$GIT_LOG"
  git_says "$@"
}

# A case overrides this. Anything it does not answer fails rather than guesses:
# an invented answer would look like a passing test.
git_says() {
  fail "the case did not say what git answers for: git $*"
}

# Nothing in a child process should reach the real git. The rest of PATH stays,
# because the library uses awk, sed and friends for real.
guard_path() {
  mkdir -p "$WORK/nogit"
  cat > "$WORK/nogit/git" <<'SHIM'
#!/bin/sh
printf 'test harness: real git reached from a child process: git %s\n' "$*" >&2
exit 97
SHIM
  chmod +x "$WORK/nogit/git"
  PATH=$WORK/nogit:$PATH
  export PATH
}

asked() {
  grep -qxF "$1" "$GIT_LOG"
}

assert_asked() {
  asked "$1" && return 0
  fail "expected git to be asked:
    $1
  it was asked:
$(sed 's/^/    /' "$GIT_LOG")"
}

assert_not_asked() {
  asked "$1" || return 0
  fail "git should not have been asked:
    $1"
}

assert_eq() {
  [ "$1" = "$2" ] && return 0
  fail "expected: [$2]
  actual:   [$1]"
}

assert_contains() {
  case "$1" in
    *"$2"*) return 0 ;;
  esac
  fail "expected to contain:
    $2
  in:
$(printf '%s\n' "$1" | sed 's/^/    /')"
}

assert_not_contains() {
  case "$1" in
    *"$2"*) fail "should not contain:
    $2
  in:
$(printf '%s\n' "$1" | sed 's/^/    /')" ;;
  esac
  return 0
}

# The library reads these from its caller. A case sets whatever else it needs.
MAIN=main
MAIN_REF=refs/remotes/origin/HEAD
VERBOSE=false
TOOL=test
BASE_OVERRIDE=''
ONLY_BRANCHES=''
DETACHED=''
PLAN=''
DOOMED=' '
WALK_DEPTH=5
MAX_DISTANCE=100
MAX_AGE_DAYS=30
EVALUATE_OLD=false
PR_MERGE_TABLE=''
PR_DETACHED_TABLE=''
PR_SOURCE=''
WT_MAP=''
MAIN_IDX=''
REMOVED_COUNT=0
RESCUED_COUNT=0
