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

FAILED=$WORK/failed

# Marks a file as well as exiting, because most of the functions under test are
# subshells: `exit 1` inside one ends the subshell and the case carries on. A
# case that ended green over a call the fake refused is what this is for.
fail() {
  printf '%s\n' "$1" >&2
  : > "$FAILED"
  exit 1
}

# A file, not a variable: the code under test calls git inside subshells, and a
# variable set in one is lost when it exits.
GIT_LOG=$WORK/git.log
: > "$GIT_LOG"

# git_says runs in a subshell, so whatever names it uses cannot reach the code
# under test. Isolating it here rather than in each definition means a case can
# write a plain function without reopening the hole: the fake once had its own
# `a` and `b` overwrite a caller's mid-loop, and a fork point was computed
# against a branch name that was no longer the branch.
git() {
  printf '%s\n' "$*" >> "$GIT_LOG"
  ( git_says "$@" )
}

# A case overrides this. Anything it does not answer fails rather than guesses:
# an invented answer would look like a passing test.
git_says() {
  fail "the case did not say what git answers for: git $*"
}

# tmux is faked the same way: a function every caller in the sourced library
# gets, answered by tmux_says in a subshell, and logged one call per line.
# A case answers only what real tmux could answer: a server with a session
# called "" lists it as an empty name, not as nothing. A claim about how tmux
# itself treats an argument belongs in tests/tmux, which runs the real one.
TMUX_LOG=$WORK/tmux.log
: > "$TMUX_LOG"

tmux() {
  printf '%s\n' "$*" >> "$TMUX_LOG"
  ( tmux_says "$@" )
}

tmux_says() {
  fail "the case did not say what tmux answers for: tmux $*"
}

tmux_asked() {
  grep -qxF "$1" "$TMUX_LOG"
}

# Nothing in a child process should reach the real git, or the real tmux. The
# rest of PATH stays, because the library uses awk, sed and friends for real.
guard_path() {
  mkdir -p "$WORK/nogit"
  cat > "$WORK/nogit/git" <<'SHIM'
#!/bin/sh
printf 'test harness: real git reached from a child process: git %s\n' "$*" >&2
exit 97
SHIM
  cat > "$WORK/nogit/tmux" <<'SHIM'
#!/bin/sh
printf 'test harness: real tmux reached from a child process: tmux %s\n' "$*" >&2
exit 97
SHIM
  chmod +x "$WORK/nogit/git" "$WORK/nogit/tmux"
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
CACHE_DIR=$WORK/cache
mkdir -p "$CACHE_DIR"
REMOVED_COUNT=0
RESCUED_COUNT=0
