#!/bin/sh
# Sync a fixed set of repos with their remotes.
# Each repo is fetched, then:
#   - only behind  → pull --rebase; abort and report if conflict
#   - only ahead   → push
#   - diverged     → report, do nothing
#   - up to date   → report, do nothing

REPOS="
$HOME/dotfiles
$HOME/.claude
$HOME/repos/@shellicar/tower
$HOME/repos/shellicar/tower
$HOME/repos/shellicar/skills
$HOME/repos/shellicar/skills-v2
$HOME/repos/fleet/claude-fleet-eagers
$HOME/repos/shellicar/claude-fleet-eagers
"

for repo in $REPOS; do
  [ -z "$repo" ] && continue

  [ -d "$repo" ] || continue

  printf '\n=== %s ===\n' "$repo"

  cd "$repo" || continue

  if ! git fetch --quiet 2>&1; then
    echo "  Fetch failed — skipping"
    continue
  fi

  if ! git rev-parse @{u} >/dev/null 2>&1; then
    echo "  No upstream configured — skipping"
    continue
  fi

  ahead=$(git rev-list @{u}..HEAD --count)
  behind=$(git rev-list HEAD..@{u} --count)

  if [ "$ahead" -eq 0 ] && [ "$behind" -eq 0 ]; then
    echo "  Up to date"

  elif [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
    echo "  Diverged (ahead $ahead, behind $behind) — skipping"

  elif [ "$behind" -gt 0 ]; then
    echo "  Behind by $behind — pulling (rebase)"
    if git pull --rebase --quiet 2>&1; then
      echo "  Done"
    else
      git rebase --abort 2>/dev/null
      stashed=0
      if [ -n "$(git status --porcelain)" ]; then
        echo "  Rebase failed — stashing local changes and retrying"
        if git stash push --quiet --include-untracked; then
          stashed=1
        else
          echo "  Stash failed — giving up"
        fi
      fi
      if [ "$stashed" -eq 1 ] || [ -z "$(git status --porcelain)" ]; then
        if git pull --rebase --quiet 2>&1; then
          echo "  Done"
        else
          git rebase --abort 2>/dev/null
          echo "  Pull failed again (conflict) — aborted"
        fi
      fi
      if [ "$stashed" -eq 1 ]; then
        if git stash pop --quiet; then
          echo "  Stash restored"
        else
          echo "  Stash pop failed — resolve manually (stash kept)"
        fi
      fi
    fi

  elif [ "$ahead" -gt 0 ]; then
    echo "  Ahead by $ahead — pushing"
    if ! git push --quiet 2>&1; then
      echo "  Push failed"
    else
      echo "  Done"
    fi
  fi

  dirty=$(git status --porcelain)
  if [ -n "$dirty" ]; then
    echo "  Dirty:"
    echo "$dirty" | sed 's/^/    /'
  fi
done
