# Sourced by a scenario, inside the container.
#
# Everything here builds a real repository and runs the real commands. That is
# the point: the pure suite replaces git, so it can prove what a command decides
# and never that carrying the decision out does what the decision said.

ROOT=/work
BIN=/repo/home/common/bin

fail() { printf 'FAIL %s\n' "$1" >&2; exit 1; }

new_repo() {
  mkdir -p "$ROOT"
  cd "$ROOT"
  git init -q -b main --bare upstream.git
  git init -q -b main repo
  cd repo
  git config user.email test@test
  git config user.name test
  git config commit.gpgsign false
  git remote add origin "$ROOT/upstream.git"
  commit A a.txt
  git push -q -u origin main
  git remote set-head origin main
}

commit() {
  printf '%s\n' "$1" > "${2:-file.txt}"
  git add -A
  git commit -qm "$1"
}

branch() {
  git switch -q -c "$1"
}

# What a squash merge leaves: the content on main under one new commit, and none
# of the branch's own commits. Every merged verdict has to cope with this.
squash_into_main() {
  git switch -q main
  git merge -q --squash "$1" >/dev/null 2>&1 || :
  git commit -qm "squash merge $1"
  git push -q origin main
  git fetch -q origin
  git switch -q "$1"
}

worktree_for() {
  git worktree add -q "$ROOT/wt-$1" "$1"
}

run_command() {
  cmd=$1
  shift
  printf '--- %s %s ---\n' "$cmd" "$*"
  # The countdown before it acts is five seconds of nothing here.
  "$BIN/$cmd" "$@" 2>&1 | sed 's/^/  /'
}

exists() {
  git rev-parse --verify --quiet "$1" >/dev/null || fail "expected to still exist: $1"
  printf '  ok   %s exists\n' "$1"
}

gone() {
  git rev-parse --verify --quiet "$1" >/dev/null && fail "expected to be gone: $1"
  printf '  ok   %s gone\n' "$1"
  return 0
}

gone_dir() {
  [ -d "$1" ] && fail "expected the directory to be gone: $1"
  printf '  ok   %s gone\n' "$1"
  return 0
}

# A rescue replays, so the original commit id is gone by design and asserting on
# it proves nothing. What has to survive is the work: the file the stray commit
# introduced, present on the rescue branch and absent from the trunk.
carries() {
  git show "$1:$2" >/dev/null 2>&1 || fail "$1 does not carry $2"
  printf '  ok   %s carries %s\n' "$1" "$2"
}

lacks() {
  git show "$1:$2" >/dev/null 2>&1 && fail "$1 unexpectedly carries $2"
  printf '  ok   %s does not carry %s\n' "$1" "$2"
  return 0
}
