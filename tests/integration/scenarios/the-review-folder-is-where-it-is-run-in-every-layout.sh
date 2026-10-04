#!/bin/sh
# Runs inside the container, against repositories built here.
#
# git review opens the top of the checkout it is run from, or the repository
# itself when it is bare and has no checkout. Where that folder is depends on
# how the repository is laid out, and only real git can say, so every layout is
# built and asked from each place git review can be run.
set -eu

# The path exists only inside the container, where run.sh mounts it.
# shellcheck source=../lib.sh
. /scenario/lib.sh
# shellcheck source=../../../home/common/lib/git-common.sh
. /repo/home/common/lib/git-common.sh

git config --global user.email test@test
git config --global user.name test
git config --global commit.gpgsign false
git config --global init.defaultBranch main
git config --global protocol.file.allow always

mkdir -p "$ROOT"
cd "$ROOT"

# Asked from <dir>, review_folder has to name <expected>.
opens() {
  got=$(cd "$1" && review_folder) || fail "review_folder failed in $1"
  [ "$got" = "$2" ] || fail "from $1: expected $2, got $got"
  printf '  ok   from %s opens %s\n' "$1" "$2"
}

echo '--- a normal clone ---'
git init -q "$ROOT/normal"
git -C "$ROOT/normal" commit -q --allow-empty -m A
mkdir "$ROOT/normal/sub"
git -C "$ROOT/normal" worktree add -q -b w "$ROOT/normal-wt"
opens "$ROOT/normal" "$ROOT/normal"
opens "$ROOT/normal/sub" "$ROOT/normal"
opens "$ROOT/normal-wt" "$ROOT/normal-wt"

echo '--- a bare repository ---'
git init -q --bare "$ROOT/bare.git"
git clone -q "$ROOT/bare.git" "$ROOT/seed" 2>/dev/null
git -C "$ROOT/seed" commit -q --allow-empty -m A
git -C "$ROOT/seed" push -q origin main
git -C "$ROOT/bare.git" worktree add -q "$ROOT/bare-wt" main
opens "$ROOT/bare.git" "$ROOT/bare.git"
opens "$ROOT/bare-wt" "$ROOT/bare-wt"

echo '--- a submodule ---'
git init -q "$ROOT/lib-src"
git -C "$ROOT/lib-src" commit -q --allow-empty -m A
git init -q "$ROOT/super"
git -C "$ROOT/super" commit -q --allow-empty -m A
git -C "$ROOT/super" submodule add -q "$ROOT/lib-src" lib
git -C "$ROOT/super/lib" worktree add -q -b w "$ROOT/lib-wt"
opens "$ROOT/super/lib" "$ROOT/super/lib"
opens "$ROOT/lib-wt" "$ROOT/lib-wt"

echo '--- a repository cloned with --separate-git-dir ---'
git init -q --bare "$ROOT/sep-src.git"
git clone -q "$ROOT/sep-src.git" "$ROOT/sep-seed" 2>/dev/null
git -C "$ROOT/sep-seed" commit -q --allow-empty -m A
git -C "$ROOT/sep-seed" push -q origin main
git clone -q --separate-git-dir "$ROOT/sep.git" "$ROOT/sep-src.git" "$ROOT/sep"
git -C "$ROOT/sep" worktree add -q -b w "$ROOT/sep-wt"
opens "$ROOT/sep" "$ROOT/sep"
opens "$ROOT/sep-wt" "$ROOT/sep-wt"

echo 'PASS the-review-folder-is-where-it-is-run-in-every-layout'
