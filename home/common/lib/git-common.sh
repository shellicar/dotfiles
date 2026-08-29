#!/bin/sh
#
# git-common.sh — what the git commands in ../bin share: reading the repository,
# deciding whether work has landed, inspecting worktrees, and carrying out a
# plan. Sourced, never executed.
#
# HOW IT IS FOUND. install.sh links home/common file by file into $HOME, keeping
# the relative path, so bin/ and lib/ arrive as ~/bin and ~/lib. Git dispatches a
# subcommand with the full path of the file it found on PATH, symlink and all,
# so `$(cd "$(dirname "$0")" && pwd)/../lib` resolves without readlink. That
# matters: BSD readlink has no -f, and the portable resolver is exactly the kind
# of thing this repo keeps having to avoid.
#
# WHAT THE CALLER OWES IT. This file defines functions and the colour variables
# and nothing else runs at source time. Everything the functions read is the
# caller's: MAIN, CACHE_DIR, TAB, NOW, VERBOSE, WALK_DEPTH, EVALUATE_OLD,
# ONLY_BRANCHES, DETACHED, PLAN, and the counters run_plan increments. Under
# `set -u` that is safe because a function only runs once the caller has set up.
#
# TOOL names the command in the -v log lines, so a shared function says which
# front-end it was speaking for.

# The colour names, the icons, PR_SOURCE and PR_HINT are defined here and read
# by the front-ends, which shellcheck cannot see from inside this file. That is
# what a library is, so the check is off for the file rather than annotated at a
# dozen assignments.
# shellcheck disable=SC2034

TOOL=${TOOL:-git}

# ── presentation ────────────────────────────────────────────────────────────

if [ -t 1 ]; then
  GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'
  DIM='\033[2m'; BOLD='\033[1m'; RESET='\033[0m'
else
  GREEN=''; YELLOW=''; RED=''; BLUE=''; DIM=''; BOLD=''; RESET=''
fi

OK='✅'; KEEP='•'; WARN='⚠️ '; NOACCESS='🚫'; EMPTYICON='≡'; UNKNOWN='?'; WOULDREMOVE='\342\235\227'

say() { printf '%b\n' "$*"; }
log() { [ "$VERBOSE" = true ] && printf '%b\n' "${DIM}[$TOOL] $*${RESET}" >&2; return 0; }

# A phase label printed before the phase runs, so a slow run shows where it is
# instead of sitting blank, then completed in place with its result. Under -v the
# label ends its own line, or the log output lands in the middle of it.
step() { printf '%b' "  ${DIM}$*${RESET} "; [ "$VERBOSE" = true ] && printf '\n'; return 0; }
step_done() { [ "$VERBOSE" = true ] && printf '    '; printf '%b\n' "${DIM}$*${RESET}"; return 0; }

# A branch or worktree untouched for a week or more is a signal it is likely
# safe to clean up, so it reads GREEN rather than a warning colour. Weeks,
# months and years are always old; "N days ago" only counts once N reaches 7,
# git showing day-granularity up to ~13 days before it switches to weeks.
age_colour() (
  case "$1" in
    *' week'*|*' month'*|*' year'*) printf '%s' "$GREEN"; return 0 ;;
    *' day'*)
      n=$(printf '%s' "$1" | awk '{print $1}')
      case "$n" in ''|*[!0-9]*) ;; *) [ "$n" -ge 7 ] && { printf '%s' "$GREEN"; return 0; } ;; esac
      ;;
  esac
  printf '%s' "$DIM"
)

# ── repository context ──────────────────────────────────────────────────────

ref_exists() { git rev-parse --verify --quiet "$1" >/dev/null 2>&1; }

ensure_in_git_repository() {
  git rev-parse --git-dir >/dev/null 2>&1 || { echo "Error: not in a git repository" >&2; exit 1; }
}

get_main_branch() (
  [ -n "$BASE_OVERRIDE" ] && { echo "$BASE_OVERRIDE"; return 0; }
  ref=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null) || {
    echo "Error: cannot determine main branch from origin/HEAD (try -b <branch>)" >&2; exit 1; }
  echo "$ref" | sed 's@^refs/remotes/origin/@@'
)

fetch_origin() {
  [ "$NO_FETCH" = true ] && { log "skipping fetch (--no-fetch)"; return 0; }
  log "fetching origin --prune ..."
  git fetch --prune origin >/dev/null 2>&1 || \
    echo "Warning: could not fetch from origin; proceeding with local data." >&2
}

# ── the merge check (the verdict) ───────────────────────────────────────────

# The stripped-diff CONTENT of a change: the diff with its ---/+++/@@/index
# header lines removed, then hashed for indexing. This is git-check.sh's
# comparison — the actual diff content, NOT a patch-id.
content_hash() {
  git diff "$1" "$2" | sed -e '/^--- /d' -e '/^+++ /d' -e '/^@@/d' -e '/^index /d' | shasum | awk '{print $1}'
}

# content_hash is a pure function of two immutable git SHAs — once a commit
# exists its diff against another commit never changes, so a cache entry
# never goes stale and needs no invalidation. Repo-local, under .git/, so it
# survives across runs but never leaks between repos.
content_hash_cached() (
  a=$1 b=$2
  key=$(printf '%s %s' "$a" "$b" | shasum | awk '{print $1}')
  file="$CACHE_DIR/$key"
  if [ -f "$file" ]; then
    h=$(cat "$file")
  else
    h=$(content_hash "$a" "$b")
    printf '%s\n' "$h" > "$file"
  fi
  # The newline matters: the main index is line-oriented, matched with grep -x.
  printf '%s\n' "$h"
)

# The PR host origin points at. Decided by the remote, not by which CLI happens
# to be installed, so a machine with both does not guess wrong.
pr_host() {
  case "$(git config --get remote.origin.url 2>/dev/null)" in
    *dev.azure.com*) echo azure ;;
    *github.com*) echo github ;;
    *) return 1 ;;
  esac
}

# org/project/repo of an Azure DevOps remote, tab separated. Both remote forms
# normalise to the same triple:
#   https://{org}@dev.azure.com/{org}/{project}/_git/{repo}
#   git@ssh.dev.azure.com:v3/{org}/{project}/{repo}
ado_coordinates() (
  url=$(git config --get remote.origin.url 2>/dev/null) || return 1
  case "$url" in
    *ssh.dev.azure.com:v3/*) path=${url#*ssh.dev.azure.com:v3/} ;;
    *) path=$(printf '%s' "${url#*dev.azure.com/}" | sed 's@/_git/@/@') ;;
  esac
  path=${path%.git}
  printf '%s\t%s\t%s\n' "$(printf '%s' "$path" | cut -d/ -f1)" "$(printf '%s' "$path" | cut -d/ -f2)" "$(printf '%s' "$path" | cut -d/ -f3)"
)

# One bulk fetch of every merged PR's source branch, its tip at merge, and the
# merge commit it made on main, instead of an API call per branch (~0.5s network
# round-trip each — 50 branches would be 25s of pure latency). Populated once,
# in the tab-separated table
# PR_MERGE_TABLE looks up from. Azure DevOps reports the source branch as a full
# ref, so it is stripped to match the plain branch names on the other side.
# az answers an auth failure with a blanket 'az logout; az login', which tears
# down every other tenant's credentials to fix one org. This is the scoped form.
# The tenant is derived rather than configured, so it cannot drift from the
# subscription beside it.
ado_login_hint() {
  local t
  [ "${2:-}" = force ] || grep -qE 'Interactive authentication is needed|TF400813|az login' "$CACHE_DIR/az-error" 2>/dev/null || return 0
  # With a profile the browser picks the identity, so naming a tenant would only
  # constrain it wrongly. Without one, the tenant is what narrows the login.
  if [ -n "$AZ_CONFIG" ]; then
    PR_HINT="  ${DIM}run: AZURE_CONFIG_DIR=$AZ_CONFIG az login --scope $ADO_RESOURCE/.default${RESET}"
    return 0
  fi
  t=$(az account list --query "[?id=='$1'].tenantId | [0]" -o tsv 2>/dev/null) || return 0
  [ -n "$t" ] && PR_HINT="  ${DIM}run: az login --tenant $t --scope $ADO_RESOURCE/.default${RESET}"
  return 0
}

fetch_pr_merges() {
  PR_MERGE_TABLE=''; PR_SOURCE='no PR host'; PR_HINT=''; AZ_CONFIG=''
  # Kept for fetch_detached_prs: minting a token costs a round trip, and the
  # coordinates are already parsed here.
  ADO_TOKEN=''; ADO_ORG=''; ADO_PROJECT=''; ADO_REPO=''
  local host coords raw sub org project repo token
  host=$(pr_host) || return 0
  case "$host" in
    azure)
      command -v az >/dev/null 2>&1 || { PR_SOURCE='azure devops, az missing'; return 0; }
      sub=$(git config --get cleanup.subscription) || { PR_SOURCE='azure devops, no subscription configured'; return 0; }
      coords=$(ado_coordinates) || return 0
      PR_SOURCE='azure devops'
      org=$(printf '%s' "$coords" | cut -f1); project=$(printf '%s' "$coords" | cut -f2); repo=$(printf '%s' "$coords" | cut -f3)
      # One az profile holds one login per subscription, so a second identity on the
      # same subscription evicts the first. A profile per org keeps both alive.
      AZ_CONFIG=$(git config --get cleanup.azconfig) || AZ_CONFIG=''
      case "$AZ_CONFIG" in "~/"*) AZ_CONFIG="$HOME/${AZ_CONFIG#\~/}" ;; esac
      [ -n "$AZ_CONFIG" ] && export AZURE_CONFIG_DIR="$AZ_CONFIG"
      log "ado org=[$org] project=[$project] repo=[$repo] sub=[$sub] azconfig=[$AZ_CONFIG]"
      # az rest authenticates as the default account and ignores the account
      # flags, which 403s against an org in another tenant, so the token is
      # fetched here and attached explicitly.
      # --subscription, never --tenant: a subscription resolves both the tenant and
      # the identity signed in for it, where --tenant names only the target and
      # leaves az using the default account's credentials. AAD then rejects them
      # with AADSTS50020 when that user is foreign to the tenant.
      token=$(az account get-access-token --subscription "$sub" --resource "$ADO_RESOURCE" --query accessToken -o tsv 2>"$CACHE_DIR/az-error") || { PR_SOURCE='azure devops, no token for subscription'; log "ado token error: $(cat "$CACHE_DIR/az-error")"; ado_login_hint "$sub" force; return 0; }
      # $top is an OData parameter, single-quoted so no shell expands it away.
      # Without it the API returns its default first page of 101, not the lot.
      raw=$(az rest --method get --skip-authorization-header --headers "Authorization=Bearer $token" --url "https://dev.azure.com/$org/$project/_apis/git/repositories/$repo/pullrequests" --uri-parameters searchCriteria.status=completed '$top=1000' api-version=7.1 --query 'value[?lastMergeCommit.commitId!=null && lastMergeSourceCommit.commitId!=null].[sourceRefName, lastMergeSourceCommit.commitId, lastMergeCommit.commitId]' -o tsv 2>"$CACHE_DIR/az-error") || { PR_SOURCE='azure devops, query failed'; log "ado query error: $(cat "$CACHE_DIR/az-error")"; ado_login_hint "$sub"; return 0; }
      # An expired session gets Azure DevOps's HTML sign-in page with a 200, so az
      # exits 0, skips --query because the body is not JSON, and prints the page.
      # Rows are therefore validated, not trusted: branch, tab, 40 hex characters.
      ADO_TOKEN=$token; ADO_ORG=$org; ADO_PROJECT=$project; ADO_REPO=$repo
      PR_MERGE_TABLE=$(printf '%s' "$raw" | sed 's@^refs/heads/@@' | awk -F'\t' 'NF==3 && $2 ~ /^[0-9a-f]{40}$/ && $3 ~ /^[0-9a-f]{40}$/')
      log "ado rows=$(printf '%s' "$PR_MERGE_TABLE" | grep -c .) of $(printf '%s' "$raw" | grep -c .) lines"
      if [ -z "$PR_MERGE_TABLE" ] && [ -n "$raw" ]; then
        PR_SOURCE='azure devops, not signed in'
        ado_login_hint "$sub" force
      fi
      ;;
    github)
      command -v gh >/dev/null 2>&1 || { PR_SOURCE='github, gh missing'; return 0; }
      PR_SOURCE='github'
      PR_MERGE_TABLE=$(gh pr list --state merged --json headRefName,headRefOid,mergeCommit --limit 1000 --jq '.[] | select(.mergeCommit != null) | [.headRefName, .headRefOid, .mergeCommit.oid] | @tsv' 2>/dev/null) || { PR_SOURCE='github, query failed'; return 0; }
      ;;
  esac
}

# The SOURCE BRANCH TIP as it was when the PR merged, looked up from the table
# fetch_pr_merges built once up front. Empty if none. This is the commit the
# branch has to still be sitting on for the PR to speak for it.
pr_head() {
  printf '%s\n' "$PR_MERGE_TABLE" | awk -F'\t' -v b="$1" '$1==b{print $2; exit}'
}

# The squash/merge commit the PR created ON MAIN. Not evidence about the branch:
# only a base to replay onto when a rescue cannot use main.
pr_merge_commit() {
  printf '%s\n' "$PR_MERGE_TABLE" | awk -F'\t' -v b="$1" '$1==b{print $3; exit}'
}

# The branch is exactly what the PR merged, and nothing since. An exact match is
# the whole test: anything else means commits the PR never carried, and those
# have to be found in main by content like any other branch's would.
pr_covers_branch() (
  head=$(pr_head "$1") || return 1
  [ -n "$head" ] || return 1
  tip=$(git rev-parse --verify --quiet "$1") || return 1
  [ "$tip" = "$head" ]
)

# Which pull requests carry each detached commit, as sha/kind/label rows. A
# failed lookup is the same as no pull request, which sends a worktree towards
# unsure, never towards removal.
#
# The two hosts answer this from opposite ends. GitHub takes a commit and names
# the pull requests carrying it, one call per worktree. Azure DevOps has a query
# shaped like that, but it returns nothing once the source branch is deleted,
# which is the only case a review worktree is ever in — so there the pull request
# list is fetched instead and each one's source branch tip is tested for ancestry
# locally.
fetch_detached_prs() {
  DETACHED_PR_TABLE=''
  local head rows raw src status id ref kind
  [ -z "$DETACHED" ] && return 0
  case "$(pr_host 2>/dev/null)" in
    github)
      command -v gh >/dev/null 2>&1 || return 0
      while IFS="$TAB" read -r head _; do
        [ -z "$head" ] && continue
        rows=$(gh api "repos/{owner}/{repo}/commits/$head/pulls" --jq '.[] | [(if .merged_at then "merged" elif .state == "open" then "open" else "closed" end), "PR #\(.number) \(.head.ref)"] | @tsv' 2>/dev/null) || continue
        [ -z "$rows" ] && continue
        DETACHED_PR_TABLE="$DETACHED_PR_TABLE$(printf '%s\n' "$rows" | awk -v h="$head" '{print h "\t" $0}')
"
      done <<EOF
$DETACHED
EOF
      ;;
    azure)
      [ -n "$ADO_TOKEN" ] || return 0
      # status=all, because a detached worktree is judged on merged, open and
      # abandoned alike. lastMergeSourceCommit is the source branch tip, which
      # is what the local ancestry test needs.
      raw=$(az rest --method get --skip-authorization-header --headers "Authorization=Bearer $ADO_TOKEN" --url "https://dev.azure.com/$ADO_ORG/$ADO_PROJECT/_apis/git/repositories/$ADO_REPO/pullrequests" --uri-parameters searchCriteria.status=all '$top=1000' api-version=7.1 --query 'value[?lastMergeSourceCommit.commitId!=null].[lastMergeSourceCommit.commitId, status, pullRequestId, sourceRefName]' -o tsv 2>/dev/null) || return 0
      printf '%s\n' "$raw" | awk -F'\t' 'NF==4 && $1 ~ /^[0-9a-f]{40}$/' > "$CACHE_DIR/ado-prs"
      # A source tip the object store no longer holds cannot be tested, so those
      # rows are dropped once here rather than failing per worktree.
      cut -f1 "$CACHE_DIR/ado-prs" | git cat-file --batch-check 2>/dev/null | awk '$2=="commit"{print $1}' > "$CACHE_DIR/ado-present"
      awk -F'\t' 'NR==FNR{p[$1];next} $1 in p' "$CACHE_DIR/ado-present" "$CACHE_DIR/ado-prs" > "$CACHE_DIR/ado-live"
      log "ado detached: $(wc -l < "$CACHE_DIR/ado-live" | tr -d ' ') of $(wc -l < "$CACHE_DIR/ado-prs" | tr -d ' ') pull request tips still local"
      while IFS="$TAB" read -r head _; do
        [ -z "$head" ] && continue
        while IFS="$TAB" read -r src status id ref; do
          git merge-base --is-ancestor "$head" "$src" 2>/dev/null || continue
          case "$status" in
            completed) kind=merged ;;
            active) kind=open ;;
            *) kind=closed ;;
          esac
          DETACHED_PR_TABLE="$DETACHED_PR_TABLE$head$TAB$kind${TAB}PR $id ${ref#refs/heads/}
"
        done < "$CACHE_DIR/ado-live"
      done <<EOF
$DETACHED
EOF
      ;;
  esac
}

# The label of a pull request of the given kind (merged/open/closed) carrying
# this commit, or empty.
detached_pr() {
  printf '%s\n' "$DETACHED_PR_TABLE" | awk -F'\t' -v h="$1" -v k="$2" '$1==h && $2==k {print $3; exit}'
}

# Past the cap the content walk is skipped: main has moved far enough that the
# branch's paths have likely been restructured out from under the comparison, so
# the walk is both the expensive check and the futile one. Distance AND age,
# never either alone — a recent branch on a fast repo is far back but still
# comparable, and an old branch on a quiet repo is only a few commits to check.
# An explicitly named --branch is never capped: naming it says what --old says.
branch_beyond_cap() (
  [ "$EVALUATE_OLD" = true ] && return 1
  [ -n "$ONLY_BRANCHES" ] && return 1
  dist=$(git rev-list --count "origin/$MAIN" "^$1" 2>/dev/null) || return 1
  [ "$dist" -gt "$MAX_DISTANCE" ] || return 1
  last=$(git log -1 --format=%ct "$1" 2>/dev/null) || return 1
  [ $(( NOW - last )) -gt $(( MAX_AGE_DAYS * 86400 )) ]
)

# Commits main has moved past the branch's fork, for the inconclusive report.
distance_from_main() { git rev-list --count "origin/$MAIN" "^$1" 2>/dev/null || echo '?'; }

# How many main commits, back from the tip, we actually need indexed this
# run: the largest base..origin/$MAIN distance among branches that fail BOTH
# the ancestor check AND the PR check and are within the evaluation cap (only
# those ever fall through to the content walk). Not a fixed constant — the true
# maximum this run needs, and 0 (skip entirely) if none qualify.
compute_max_walk_depth() (
  max=0
  revs=${ONLY_BRANCHES:-$(git for-each-ref --format '%(refname:short)' refs/heads/)}
  # Detached heads reach the same content walk, so the index has to be deep
  # enough for them too, not just for the branches.
  [ -z "$ONLY_BRANCHES" ] && revs="$revs $(printf '%s' "$DETACHED" | cut -f1)"
  for rev in $revs; do
    [ "$rev" = "$MAIN" ] && continue
    base=$(git merge-base "$rev" "origin/$MAIN" 2>/dev/null) || continue
    git merge-base --is-ancestor "$rev" "origin/$MAIN" 2>/dev/null && continue
    # Same test the verdict uses, or the index is sized for fewer branches than
    # actually reach the content walk and their answers come out wrong.
    pr_covers_branch "$rev" && continue
    branch_beyond_cap "$rev" && continue
    dist=$(git rev-list --count "$base..origin/$MAIN" 2>/dev/null) || continue
    [ "$dist" -gt "$max" ] && max=$dist
  done
  echo "$max"
)

# ONE shared index of main's commit-content hashes, built once for the whole
# run at the size compute_max_walk_depth actually needs — not per branch, not
# a fixed 500. Every pending branch's own range is a prefix of this same set
# (both count back from origin/$MAIN's tip), so one walk covers all of them.
build_shared_main_index() {
  local depth c p
  depth=$(compute_max_walk_depth)
  # Repo-local and truncated per run, so nothing is left behind in $TMPDIR.
  MAIN_IDX="$CACHE_DIR/main-index"
  : > "$MAIN_IDX" || { echo "Error: cannot write $MAIN_IDX" >&2; exit 1; }
  [ "$depth" -eq 0 ] && return 0
  git rev-list -n "$depth" "origin/$MAIN" | while read -r c; do
    p=$(git rev-parse "$c^" 2>/dev/null) || continue
    content_hash_cached "$p" "$c"
  done | sort -u > "$MAIN_IDX"
}

# Walk the branch tip-first; the first commit whose cumulative content
# (merge-base..C) is found in main is the join point. Echoes the number of
# commits sitting after that join point (0 = fully merged), -1 if no join point
# is found within WALK_DEPTH, or -2 if the branch is past the evaluation cap and
# the content walk was never run.
#
# PR checked FIRST, and only ever as an EXACT MATCH: the branch tip is the same
# commit the PR merged, so the PR is a statement about this branch and not just
# about some commits it once had. A squash merge leaves none of the branch's
# commits in main, so without this the content walk has nothing to find and the
# branch reads as unmerged, which is what the PR is here to answer.
#
# Anything short of an exact match falls through. A merged PR does NOT mean the
# branch is in main: commit to it afterwards and the extra work exists nowhere
# else, while the PR still says merged. An earlier version trusted the PR in
# that case and deleted a branch, its worktree, and the one commit that had been
# added after the merge. The content walk below is what covers the difference.
commits_not_in_main() (
  # rev, not branch: a detached worktree's head comes through here too.
  rev=$1
  base=$(git merge-base "$rev" "origin/$MAIN" 2>/dev/null) || { echo -1; return; }
  # Fully contained in main (0 unique commits — includes a branch sitting at main).
  git merge-base --is-ancestor "$rev" "origin/$MAIN" && { echo 0; return; }

  pr_covers_branch "$rev" && { echo 0; return; }

  # Cheap checks done and unresolved; only the expensive one is left.
  branch_beyond_cap "$rev" && { echo -2; return; }

  # Only WALK_DEPTH diffs against the rev's OWN history, tip-first, each
  # checked against the shared index built once for the whole run.
  i=0
  for c in $(git rev-list -n "$WALK_DEPTH" "$base..$rev"); do
    h=$(content_hash_cached "$base" "$c")
    if [ -s "$MAIN_IDX" ] && grep -qxF "$h" "$MAIN_IDX"; then
      echo "$i"; return
    fi
    i=$((i + 1))
  done
  echo -1
)

# ── the gone indicator (cross-check only) ───────────────────────────────────

branch_has_upstream() { git config --get "branch.$1.remote" >/dev/null; }

# Had an upstream that is now gone (remote branch deleted). No upstream at all
# is not "gone" — it is a local-only branch.
branch_upstream_gone() (
  remote=$(git config --get "branch.$1.remote") || return 1
  merge=$(git config --get "branch.$1.merge") || return 1
  ref_exists "refs/remotes/$remote/${merge#refs/heads/}" && return 1
  return 0
)

# ── worktrees ───────────────────────────────────────────────────────────────

worktree_of() {
  printf '%s\n' "$WT_MAP" | awk -F'\t' -v b="$1" '$1==b{print $2; exit}'
}

worktree_dirty() { [ -n "$(git -C "$1" status --porcelain 2>/dev/null)" ]; }

# A branch this run is going to delete. Its name is in the plan, which the branch
# pass finishes building before the detached pass starts.
doomed_branch() {
  printf '%s' "$PLAN" | awk -F"$TAB" -v b="$1" '$1=="delete" && $2==b {found=1} END {exit !found}'
}

# The first branch, remote branch or tag containing the commit, or empty. Local
# branches sort ahead of remotes and tags, so a local name is preferred.
#
# A branch already in the plan does not count. It is about to stop existing, so
# keeping a worktree "because that branch holds the commit" states a reason that
# this same run makes false a few seconds later.
commit_on_ref() (
  git for-each-ref --contains "$1" --format='%(refname:short)' refs/heads refs/remotes refs/tags 2>/dev/null |
    while read -r r; do
      doomed_branch "${r#origin/}" && continue
      printf '%s\n' "$r"
      break
    done
)

# The ignored files a worktree removal takes with it. Neither git status
# --porcelain nor git worktree remove counts them, so a worktree whose only
# extra content is ignored reads as clean and is removed with that content
# still inside it. Fully-ignored directories collapse to a single entry, so the
# list stays short, and it is capped regardless.
worktree_ignored() (
  all=$(git -C "$1" status --porcelain --ignored 2>/dev/null | sed -n 's/^!! //p')
  [ -z "$all" ] && return 0
  count=$(printf '%s\n' "$all" | grep -c .)
  list=$(printf '%s\n' "$all" | head -6 | awk '{ if (NR > 1) printf ", "; printf "%s", $0 } END { print "" }')
  [ "$count" -gt 6 ] && list="$list, +$((count - 6)) more"
  printf '%s ignored entries: %s\n' "$count" "$list"
)

say_ignored() {
  [ -n "$1" ] && say "     ${DIM}↳ also deletes $1${RESET}"
  return 0
}

# Reason a worktree must not be touched, or empty. Dirty ALWAYS blocks — there is
# no case where uncommitted work is worth risking.
#
# Standing in a worktree is NOT a reason. git will remove the one you are in, and
# the only casualty is a shell whose directory has gone, which a cd fixes. This
# script runs from the main working tree (see the chdir at the bottom), which git
# refuses to remove, so its own footing is never what is being deleted.
worktree_block_reason() {
  [ -z "$1" ] && return 0
  worktree_dirty "$1" && { echo "worktree has uncommitted changes"; return 0; }
  return 0
}

# Remove worktree first, then branch. Always -D, because the caller has already
# proved the branch tip is reachable from origin/$MAIN and that is the guarantee
# that matters. Plain -d checks something else: the branch's upstream if that ref
# still resolves, and otherwise HEAD. With the remote branch gone it falls back to
# whichever worktree you happen to be standing in, so it refuses branches that are
# provably safe.
remove_branch() (
  b=$1 w=$2
  if [ -n "$w" ]; then
    git worktree remove "$w" >/dev/null 2>&1 || { echo "worktree remove failed"; return 1; }
  fi
  git branch -D "$b" >/dev/null 2>&1 || { echo "branch delete failed"; return 1; }
  echo removed
  return 0
)

# ── verdicts ──────────────────────────────────────────────────────────────
#
# The decision, with no opinion about how it is shown. A front-end asks and then
# says it in its own words, which is what lets two of them agree.

# A branch, as: class, commits not in main, commits ahead, gone, worktree.
#   empty        identical to main, nothing of its own
#   merged       its work is in main
#   review       merged up to a point, with N commits sitting on top
#   suspect      the remote branch is gone but the content cannot be found
#   inconclusive too far behind to have been evaluated at all
#   unmerged     work of its own, not in main
branch_verdict() (
  b=$1
  ahead=$(git rev-list --count "origin/$MAIN..$b" 2>/dev/null || echo '?')
  n=$(commits_not_in_main "$b")
  gone=false; branch_upstream_gone "$b" && gone=true
  wt=$(worktree_of "$b")
  if [ "$n" = 0 ] && [ "$ahead" = 0 ]; then
    class=empty
  elif [ "$n" = 0 ]; then
    class=merged
  elif [ "$n" -gt 0 ]; then
    class=review
  elif [ "$n" = -2 ]; then
    class=inconclusive
  elif [ "$gone" = true ]; then
    class=suspect
  else
    class=unmerged
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$class" "$n" "$ahead" "$gone" "$wt"
)

# A worktree with no branch on it, as: class, then the reason in words.
#   blocked  uncommitted changes, so nothing is on offer whatever else is true
#   landed   its work is in main, or a merged pull request carries it
#   live     a branch still holds it, or an open pull request does
#   unsure   nothing claims it either way
#
# The order is the decision. Uncommitted first because it outranks everything;
# landed before live because a branch holding a commit whose work is already in
# main is not a reason to keep the checkout.
detached_verdict() (
  wt=$1 head=$2
  r=$(worktree_block_reason "$wt")
  [ -n "$r" ] && { printf 'blocked\t%s\n' "$r"; return 0; }

  [ "$(commits_not_in_main "$head")" = 0 ] && { printf 'landed\twork already in main\n'; return 0; }
  pr=$(detached_pr "$head" merged)
  [ -n "$pr" ] && { printf 'landed\tmerged in %s\n' "$pr"; return 0; }

  r=$(commit_on_ref "$head")
  [ -n "$r" ] && { printf 'live\ton %s\n' "$r"; return 0; }
  pr=$(detached_pr "$head" open)
  [ -n "$pr" ] && { printf 'live\t%s is open\n' "$pr"; return 0; }

  pr=$(detached_pr "$head" closed)
  [ -n "$pr" ] && { printf 'unsure\t%s closed without merging\n' "$pr"; return 0; }
  printf 'unsure\ton no branch, in no pull request\n'
)

# ── bringing main in ────────────────────────────────────────────────────────

# Has this branch already merged origin/$MAIN into itself? Then it keeps
# merging: a rebase would flatten that merge away and discard whatever was
# resolved in it. The test is the merge commits' parents past the first, not the
# merge commits themselves. 'git pull' without --rebase also writes a merge
# commit, but of the branch's own remote, which is not main and is no reason to
# stop rebasing.
# Echoes the merge commit that brought main in, for a caller that wants to name
# it. Takes a worktree path, so '.' for the one you are standing in.
branch_merged_main() (
  wt=$1
  pairs=$(git -C "$wt" rev-list --merges --parents "origin/$MAIN..HEAD" | awk '{ for (i = 3; i <= NF; i++) print $1, $i }')
  while IFS=' ' read -r commit parent; do
    [ -n "$parent" ] || continue
    if git -C "$wt" merge-base --is-ancestor "$parent" "origin/$MAIN"; then
      echo "$commit"
      return 0
    fi
  done <<EOF
$pairs
EOF
  return 1
)

# Where the branch was cut: the parent of the oldest commit on it that no other
# ref can reach. Empty when the branch has nothing of its own.
#
# This is what a rebase has to be given. Plain 'git rebase origin/$MAIN' replays
# everything back to the merge-base, which for a branch cut from another branch
# is where THAT branch left main, so it replays the other branch's commits too
# and force-pushes them back rewritten under new ids.
fork_point() (
  b=$1
  others=$(git for-each-ref --format='%(refname)' refs/heads refs/remotes |
    grep -vxF "refs/heads/$b" | grep -vxF "refs/remotes/origin/$b") || others=''
  # shellcheck disable=SC2086  # deliberate split: --not takes many refs
  oldest=$(git rev-list "origin/$MAIN..$b" --not $others | tail -1)
  [ -n "$oldest" ] || return 1
  git rev-parse --verify --quiet "$oldest^"
)

# The branch this one was cut from, or empty for the normal case of one cut from
# main. One cheap test does the discriminating: if the fork parent is on main
# there is nothing to look at, and a ref lookup on it would otherwise match every
# branch cut from main at or after that commit, which is all of them.
#
# Neither rebase is right for a branch cut from another branch. Plain rebase
# duplicates the parent's commits onto it; a fork-point rebase drops them and
# leaves it built on nothing. So the caller offers no update at all and names the
# branch it is tangled with, for you to look at.
branch_cut_from() (
  b=$1 base=$2
  [ -n "$base" ] || return 0
  git merge-base --is-ancestor "$base" "origin/$MAIN" 2>/dev/null && return 0
  git for-each-ref --contains "$base" --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null |
    while read -r r; do
      n=${r#origin/}
      [ "$n" = "$b" ] && continue
      printf '%s\n' "$n"
      break
    done
)

# How to bring main into this worktree, as: action, then what it needs.
#   ff              the default branch itself, fast-forward only
#   merge           it has merged main before, so it merges again
#   rebase  <base>  replayed from where it was cut
#   none    <why>   nothing is on offer, and why
#
# The strategy only. Whether the tree is dirty, whether it is behind at all and
# whether to push afterwards are the caller's, because the commands differ on
# those and agree on this.
update_verdict() (
  wt=$1 b=$2
  [ "$b" = "$MAIN" ] && { printf 'ff\t-\n'; return 0; }
  branch_merged_main "$wt" >/dev/null && { printf 'merge\t-\n'; return 0; }
  base=$(fork_point "$b") || base=''
  parent=$(branch_cut_from "$b" "$base")
  [ -n "$parent" ] && { printf 'none\tcut from %s, not from %s\n' "$parent" "$MAIN"; return 0; }
  # No commit of its own that nothing else reaches, which happens at the bottom
  # of a stack: the branch cut from this one has all of them, so there is no
  # fork point to replay from.
  [ -z "$base" ] && { printf 'none\tanother branch already has every commit on it\n'; return 0; }
  printf 'rebase\t%s\n' "$base"
)

# Carry out one update. A conflict is aborted and reported, never left half
# done. A merge rewrites nothing, so its push is an ordinary one; a rebase
# rewrote history, so its push needs the lease, which is only sound because the
# caller fetched once at the start of this run and nothing has moved since.
#
# The branch name is named to git, not the sha behind it: git builds a merge
# message from what it is given, and a raw sha writes "Merge commit '<sha>'".
run_update() {
  local act=$1 b=$2 wt=$3 base push=no
  git -C "$wt" rev-parse --verify --quiet '@{u}' >/dev/null 2>&1 && push=yes

  case "$act" in
    ff)
      if git -C "$wt" merge --ff-only --quiet "origin/$MAIN" 2>/dev/null; then
        say "  ${GREEN}${OK}${RESET} $b fast-forwarded"
      else
        say "  ${YELLOW}${WARN}${RESET}$b: cannot fast-forward (local commits?), skipped"
      fi
      return 0
      ;;
    merge)
      if ! git -C "$wt" merge --quiet --no-edit "origin/$MAIN" >/dev/null 2>&1; then
        git -C "$wt" merge --abort 2>/dev/null
        say "  ${YELLOW}${WARN}${RESET}$b: merge conflict, aborted and untouched"
        return 0
      fi
      if [ "$push" = yes ] && ! git -C "$wt" push --quiet 2>/dev/null; then
        say "  ${YELLOW}${WARN}${RESET}$b: merged, but the push failed — push it yourself"
        return 0
      fi
      say "  ${GREEN}${OK}${RESET} $b merged origin/$MAIN"
      return 0
      ;;
  esac

  base=$(fork_point "$b") || base=''
  [ -n "$base" ] || { say "  ${YELLOW}${WARN}${RESET}$b: cannot find where it was cut from, skipped"; return 0; }
  if ! git -C "$wt" rebase --quiet --onto "origin/$MAIN" "$base" >/dev/null 2>&1; then
    git -C "$wt" rebase --abort 2>/dev/null
    say "  ${YELLOW}${WARN}${RESET}$b: rebase conflict, aborted and untouched"
    return 0
  fi
  if [ "$push" = yes ] && ! git -C "$wt" push --quiet --force-with-lease 2>/dev/null; then
    say "  ${YELLOW}${WARN}${RESET}$b: rebased, but the push was refused (the remote moved) — push it yourself"
    return 0
  fi
  say "  ${GREEN}${OK}${RESET} $b rebased onto origin/$MAIN"
}

# ── the plan, and carrying it out ───────────────────────────────────────────

# Append one action to the plan. Fields are tab separated and never empty ('-'
# stands in for an absent worktree or an unused rescue field), because tab is
# IFS whitespace and consecutive tabs would otherwise collapse into one.
plan_add() {
  PLAN="${PLAN}$1${TAB}$2${TAB}$3${TAB}$4${TAB}$5
"
}

# Replay the stray commits (join..branch) onto rescue/<branch> in an isolated
# scratch worktree, so a failed attempt never touches your branches or
# checkouts, then delete the original. Main first; on conflict the PR merge
# commit; if both conflict, left alone.
run_rescue() {
  local branch=$1 join=$2 n=$3 wt=$4 dst="rescue/$branch" tmp base_used pr_mc rc outcome

  tmp=$(mktemp -d) || return 1
  git worktree add -q --detach "$tmp" "origin/$MAIN" 2>/dev/null || {
    rmdir "$tmp" 2>/dev/null
    say "     ${YELLOW}↳ rescue setup failed${RESET}"; return 1; }

  base_used=main
  ( cd "$tmp" && git switch -q -c "$dst" "$branch" && git rebase -q --onto "origin/$MAIN" "$join" ) 2>/dev/null
  rc=$?
  if [ "$rc" -ne 0 ]; then
    ( cd "$tmp" && git rebase --abort >/dev/null 2>&1; git switch -q --detach 2>/dev/null; git branch -D "$dst" >/dev/null 2>&1 )
    pr_mc=$(pr_merge_commit "$branch")
    if [ -n "$pr_mc" ]; then
      base_used="PR merge ${pr_mc}"
      ( cd "$tmp" && git switch -q -c "$dst" "$branch" && git rebase -q --onto "$pr_mc" "$join" ) 2>/dev/null
      rc=$?
      [ "$rc" -ne 0 ] && ( cd "$tmp" && git rebase --abort >/dev/null 2>&1; git switch -q --detach 2>/dev/null; git branch -D "$dst" >/dev/null 2>&1 )
    fi
  fi

  git worktree remove "$tmp" >/dev/null 2>&1 || git worktree prune >/dev/null 2>&1

  if [ "$rc" -ne 0 ]; then
    say "     ${YELLOW}↳ conflicts on both bases — left for manual${RESET}"; return 1
  fi

  # Stray is now preserved on $dst; the original's merged part is in main.
  outcome=$(remove_branch "$branch" "$wt")
  if [ "$outcome" = removed ]; then
    RESCUED_COUNT=$((RESCUED_COUNT + 1))
    say "     ${GREEN}↳ rescued $n → $dst (onto $base_used); original removed${RESET}"
  else
    say "     ${YELLOW}↳ rescued to $dst, but original $outcome${RESET}"
  fi
}

# ── execute (do exactly what the plan said) ─────────────────────────────

# Decides nothing. Every choice was made in the pass above and is already on
# screen; this walks the recorded actions and carries them out in order.
run_plan() {
  local action branch join n wt outcome
  while IFS="$TAB" read -r action branch join n wt; do
    [ -z "$action" ] && continue
    [ "$wt" = - ] && wt=''
    case "$action" in
      delete)
        outcome=$(remove_branch "$branch" "$wt")
        if [ "$outcome" = removed ]; then
          REMOVED_COUNT=$((REMOVED_COUNT + 1))
          say "  ${GREEN}${OK}${RESET} $branch removed"
        else
          say "  ${YELLOW}${WARN}${RESET}$branch: $outcome, skipped"
        fi
        ;;
      detached)
        if git worktree remove "$wt" >/dev/null 2>&1; then
          REMOVED_COUNT=$((REMOVED_COUNT + 1))
          say "  ${GREEN}${OK}${RESET} $branch removed"
        else
          say "  ${YELLOW}${WARN}${RESET}$branch: worktree remove failed, skipped"
        fi
        ;;
      rescue)
        say "  $branch"
        run_rescue "$branch" "$join" "$n" "$wt"
        ;;
      ff|merge|rebase)
        run_update "$action" "$branch" "$wt"
        ;;
    esac
  done <<EOF
$PLAN
EOF
}
