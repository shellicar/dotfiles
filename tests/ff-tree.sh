# Sourced by the ff cases, after harness.sh.
#
# ff only calls find, so its cases use a real directory tree rather than a fake.
# The tree's root stands in for a directory Claude was started in. Below it is
# a repo with worktrees of its own, a worktree in which Claude was started
# again, and a folder called worktrees that belongs to no Claude.

FF_ROOT=$WORK/tree
for f in \
  a.py \
  .claude/worktrees/one/a.py \
  .claude/worktrees/one/.claude/worktrees/three/d.py \
  repo/b.py \
  repo/.claude/worktrees/two/b.py \
  docs/worktrees/c.py; do
  mkdir -p "$FF_ROOT/$(dirname "$f")"
  : > "$FF_ROOT/$f"
done

# ff_in DIR ARGS...: what ff prints when run from DIR, as paths relative to DIR,
# sorted, so a case can compare whole lists. HOME is moved so the prunes
# anchored to it can't reach the tree.
ff_in() {
  ff_dir=$1; shift
  (cd "$ff_dir" && HOME=$WORK/home "$REPO/home/common/bin/ff" "$@") |
    sed "s|^$ff_dir/||" | sort
}

# ff_status ARGS...: ff's exit status when run from the tree's root.
ff_status() {
  (cd "$FF_ROOT" && HOME=$WORK/home "$REPO/home/common/bin/ff" "$@") >/dev/null 2>&1
  echo $?
}
