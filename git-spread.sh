#!/bin/sh
# Spread origin/main into every worktree of the current repo.
# Dry run by default; --apply to act; --stash to stash dirty trees first.
#   git spread                 what would happen
#   git spread --apply         rebase each worktree onto origin/main
#   git spread --stash         dry run, counting dirty trees as stashable
#   git spread --stash --apply stash -u, rebase, pop
# Per worktree: main fast-forwards only; others rebase onto origin/main;
# a conflicted rebase is aborted and reported, never left half-done.
# Upstreams: a branch that has genuinely diverged from its own remote is
# skipped (resolve the branch's own story first). A branch whose upstream
# was an ancestor is rebased and then pushed --force-with-lease — safe here
# because the lease reflects the fetch this same run just did.

apply=0
stash=0
for arg in "$@"; do
  case "$arg" in
    --apply) apply=1 ;;
    --stash) stash=1 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

git rev-parse --git-dir >/dev/null 2>&1 || { echo "not a git repo" >&2; exit 2; }

echo "fetching origin (prune)..."
git fetch --quiet --prune origin || { echo "❌ fetch failed" >&2; exit 1; }
target=$(git rev-parse --verify --quiet origin/main) || { echo "❌ no origin/main" >&2; exit 1; }

git worktree list --porcelain | awk '/^worktree /{print substr($0,10)}' | while IFS= read -r wt; do
  branch=$(git -C "$wt" symbolic-ref --quiet --short HEAD)
  if [ -z "$branch" ]; then
    printf '⚠️  %s: detached HEAD — skipping\n' "$wt"
    continue
  fi

  dirty=$(git -C "$wt" status --porcelain)
  behind=$(git -C "$wt" rev-list --count "HEAD..$target")
  ahead=$(git -C "$wt" rev-list --count "$target..HEAD")

  upstream=$(git -C "$wt" rev-parse --verify --quiet '@{u}')
  # Upstream configured but the remote-tracking ref pruned away: the remote
  # branch was deleted (merged PR). Not ours to rebase - it's a cleanup
  # candidate.
  if [ -z "$upstream" ] && [ -n "$(git -C "$wt" config "branch.$branch.merge")" ]; then
    printf '🧹 %s [%s]: upstream gone (merged and deleted?) — skipping, cleanup candidate\n' "$wt" "$branch"
    continue
  fi
  push_after=0
  if [ -n "$upstream" ] && [ "$branch" != "main" ]; then
    if git -C "$wt" merge-base --is-ancestor "$upstream" HEAD; then
      push_after=1
    else
      printf '⛔ %s [%s]: diverged from its own remote — resolve that first, skipping\n' "$wt" "$branch"
      continue
    fi
  fi

  if [ "$behind" -eq 0 ]; then
    printf '✅ %s [%s]: up to date with origin/main\n' "$wt" "$branch"
    continue
  fi

  if [ -n "$dirty" ] && [ "$stash" -eq 0 ]; then
    printf '⚠️  %s [%s]: dirty — skipping (use --stash)\n' "$wt" "$branch"
    continue
  fi

  verb="rebase onto"
  [ "$branch" = "main" ] && verb="fast-forward to"

  if [ "$apply" -eq 0 ]; then
    extra=""
    [ -n "$dirty" ] && extra=" (would stash first)"
    [ "$push_after" -eq 1 ] && extra="$extra + force-push (with lease)"
    printf '▶️  %s [%s]: would %s origin/main (behind %s, ahead %s)%s\n' \
      "$wt" "$branch" "$verb" "$behind" "$ahead" "$extra"
    continue
  fi

  stashed=0
  if [ -n "$dirty" ]; then
    if git -C "$wt" stash push --quiet --include-untracked; then
      stashed=1
    else
      printf '❌ %s [%s]: stash failed — skipping\n' "$wt" "$branch"
      continue
    fi
  fi

  if [ "$branch" = "main" ]; then
    if git -C "$wt" merge --ff-only --quiet "$target" 2>/dev/null; then
      printf '✅ %s [main]: fast-forwarded\n' "$wt"
    else
      printf '⚠️  %s [main]: cannot fast-forward (local commits?) — skipped\n' "$wt"
    fi
  else
    if git -C "$wt" rebase --quiet "$target" >/dev/null 2>&1; then
      if [ "$push_after" -eq 1 ]; then
        if git -C "$wt" push --quiet --force-with-lease 2>/dev/null; then
          printf '✅ %s [%s]: rebased onto origin/main, force-pushed (lease held)\n' "$wt" "$branch"
        else
          printf '⚠️  %s [%s]: rebased, but push refused (lease failed — remote moved?) — push manually\n' "$wt" "$branch"
        fi
      else
        printf '✅ %s [%s]: rebased onto origin/main\n' "$wt" "$branch"
      fi
    else
      git -C "$wt" rebase --abort 2>/dev/null
      printf '⚠️  %s [%s]: rebase conflict — aborted, untouched\n' "$wt" "$branch"
    fi
  fi

  if [ "$stashed" -eq 1 ]; then
    if git -C "$wt" stash pop --quiet; then
      printf '   stash restored\n'
    else
      printf '❌ %s [%s]: stash pop failed — resolve manually (stash kept)\n' "$wt" "$branch"
    fi
  fi
done
