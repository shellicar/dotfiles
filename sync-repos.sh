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
$HOME/repos/shellicar/skills
$HOME/repos/fleet/claude-fleet-eagers
$HOME/repos/shellicar/claude-fleet-eagers
"

for repo in $REPOS; do
  [ -z "$repo" ] && continue

  printf '\n=== %s ===\n' "$repo"

  if ! cd "$repo" 2>/dev/null; then
    echo "  Cannot enter directory — skipping"
    continue
  fi

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
    if ! git pull --rebase --quiet 2>&1; then
      git rebase --abort 2>/dev/null
      echo "  Pull failed (conflict or dirty tree) — aborted"
    else
      echo "  Done"
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
