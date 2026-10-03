#!/bin/sh
# Sync a fixed set of repos with their remotes, every worktree of each.
# Each repo is fetched once (a failed fetch skips the repo), then every
# worktree with a branch checked out, the root checkout included, goes through
# the same routine. Detached worktrees are skipped, and so is anything under
# .claude/worktrees/: those are Claude agent worktrees, local by design.
#
# With an upstream:
#   - up to date   → report, do nothing
#   - only ahead   → push
#   - only behind  → pull --rebase --autostash (git sets local changes aside
#                    and puts them back; this script never stashes itself)
#   - diverged     → report, do nothing
# Without an upstream:
#   - commits that origin/HEAD doesn't have → push -u origin <branch>
#   - none         → report, do nothing, so no remote branch is created
#                    sitting at origin/HEAD
#
# A failed push or pull shows git's own output (the pre-push hook's rejection
# of a branch name, for one) and the script carries on with the next worktree.
#
# Exit status is 1 if anything was marked ❌ (a failed fetch, pull or push, a
# worktree directory that is gone, no origin/HEAD to compare against), once
# every repo has been through; 0 otherwise. ⚠️ outcomes and skips are not
# failures.

# Set to 1 by any ❌. sync_worktree runs in the current shell (the worktree
# loop's input is a redirection, not a pipe), so its setting survives.
failed=0

REPOS="
$HOME/dotfiles
$HOME/.claude
$HOME/repos/@shellicar/tower
$HOME/repos/shellicar/tower
$HOME/repos/shellicar/skills
$HOME/repos/shellicar/skills-v2
$HOME/repos/shellicar/skills-v2.5
$HOME/repos/shellicar/skills-v3
$HOME/repos/fleet/claude-fleet-eagers
$HOME/repos/shellicar/claude-fleet-eagers
"

# sync_worktree <path> <branch>
sync_worktree() {
  wt_path=$1
  branch=$2

  printf '\n  --- %s [%s] ---\n' "$wt_path" "$branch"

  # A worktree git still lists but whose directory is gone (prunable) is
  # reported and skipped, unlike a missing repo, which the REPOS loop passes
  # over in silence. Reporting keeps the stale entry visible.
  if [ ! -d "$wt_path" ]; then
    echo "    ❌ Directory missing, skipping"
    failed=1
    return
  fi

  if git -C "$wt_path" rev-parse --verify --quiet '@{u}' >/dev/null 2>&1; then
    ahead=$(git -C "$wt_path" rev-list '@{u}..HEAD' --count)
    behind=$(git -C "$wt_path" rev-list 'HEAD..@{u}' --count)

    if [ "$ahead" -eq 0 ] && [ "$behind" -eq 0 ]; then
      echo "    ✅ Up to date ($(git -C "$wt_path" rev-parse --short HEAD))"

    elif [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
      echo "    ⚠️ Diverged (ahead $ahead, behind $behind): local $(git -C "$wt_path" rev-parse --short HEAD) vs upstream $(git -C "$wt_path" rev-parse --short '@{u}'), skipping"

    elif [ "$behind" -gt 0 ]; then
      echo "    Behind by $behind, pulling (rebase, autostash)"
      if git -C "$wt_path" pull --rebase --autostash --quiet 2>&1; then
        # pull exits 0 even when putting the local changes back conflicts:
        # the worktree is left with conflict markers and git keeps the
        # changes as an entry on the repo's stash list. This only reports it:
        # nothing resets the worktree or touches the stash entry, and git's
        # own message above says how to resolve it.
        if [ -n "$(git -C "$wt_path" diff --name-only --diff-filter=U)" ]; then
          echo "    ⚠️ Pulled ($(git -C "$wt_path" rev-parse --short HEAD)), but putting local changes back conflicted; they are also kept on the stash list"
        else
          echo "    ✅ Done ($(git -C "$wt_path" rev-parse --short HEAD))"
        fi
      else
        echo "    ❌ Pull failed"
        failed=1
      fi

    elif [ "$ahead" -gt 0 ]; then
      echo "    Ahead by $ahead, pushing"
      if git -C "$wt_path" push --quiet 2>&1; then
        echo "    ✅ Done"
      else
        echo "    ❌ Push failed"
        failed=1
      fi
    fi

  elif [ -n "$(git -C "$wt_path" config "branch.$branch.merge")" ]; then
    # The branch has an upstream configured but its remote-tracking ref is
    # gone (fetch.prune removes it once the remote branch is deleted, e.g.
    # after a PR merges), so this reports and skips. Treating it as "no
    # upstream" would push -u it again whenever it has commits origin/HEAD
    # lacks, which a squash-merged branch always has: that recreates the
    # branch the PR just deleted. The cost is that a remote branch deleted by
    # mistake is never restored by this script.
    printf '    ⚠️ Upstream %s/%s is gone, skipping\n' "$(git -C "$wt_path" config "branch.$branch.remote")" "$(git -C "$wt_path" config "branch.$branch.merge" | sed 's|^refs/heads/||')"

  else
    # With no refs/remotes/origin/HEAD (never set, or no remote called
    # origin) there is nothing to compare against, so this reports and skips
    # rather than acting on a guess about which branch is the trunk.
    if ! new=$(git -C "$wt_path" rev-list --count 'refs/remotes/origin/HEAD..HEAD' 2>/dev/null); then
      echo "    ❌ No upstream and no origin/HEAD to compare against, skipping"
      failed=1
    elif [ "$new" -eq 0 ]; then
      echo "    ✅ No upstream, nothing beyond origin/HEAD, nothing to push ($(git -C "$wt_path" rev-parse --short HEAD))"
    else
      echo "    No upstream, $new commit(s) beyond origin/HEAD, pushing to origin/$branch"
      if git -C "$wt_path" push --quiet -u origin "$branch" 2>&1; then
        echo "    ✅ Done"
      else
        echo "    ❌ Push failed"
        failed=1
      fi
    fi
  fi

  dirty=$(git -C "$wt_path" status --porcelain)
  if [ -n "$dirty" ]; then
    echo "    Dirty:"
    printf '%s\n' "$dirty" | sed 's/^/      /'
  fi
}

for repo in $REPOS; do
  [ -z "$repo" ] && continue

  [ -d "$repo" ] || continue

  printf '\n=== %s ===\n' "$repo"

  cd "$repo" || continue

  if ! git fetch --quiet 2>&1; then
    echo "  ❌ Fetch failed, skipping"
    failed=1
    continue
  fi

  # One record per worktree, each ended by a blank line. The list is read on
  # fd 3 so that git, and anything it prompts through, keeps the terminal as
  # stdin. The extra blank line ends the last record, whose terminator the
  # command substitution strips.
  wt=
  wt_branch=
  wt_detached=
  while IFS= read -r line <&3; do
    case "$line" in
      'worktree '*) wt=${line#worktree } ;;
      'branch refs/heads/'*) wt_branch=${line#branch refs/heads/} ;;
      detached) wt_detached=1 ;;
      '')
        if [ -n "$wt" ]; then
          case "$wt" in
            */.claude/worktrees/*) ;;
            *)
              if [ -n "$wt_branch" ]; then
                sync_worktree "$wt" "$wt_branch"
              elif [ -n "$wt_detached" ]; then
                printf '\n  --- %s [detached] ---\n    Detached, skipping\n' "$wt"
              fi
              ;;
          esac
        fi
        wt=
        wt_branch=
        wt_detached=
        ;;
    esac
  done 3<<EOF
$(git worktree list --porcelain)

EOF
done

exit "$failed"
