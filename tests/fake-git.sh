# A fake git: a commit graph and a set of refs in files, and the operations
# these commands use, answered from that model.
#
# It models parents, not just refs, because the questions that decide whether
# work gets destroyed are reachability questions. A fake that answered
# rev-list and merge-base from canned strings lets a test encode a repository
# state git cannot produce, which passes whatever the behaviour is.
#
# Refs are held under their full names, and a short name is resolved the way git
# resolves one, tags before heads.

REFS=$WORK/refs
PARENTS=$WORK/parents
HEAD_REF=$WORK/head
WORKTREES=$WORK/worktrees
: > "$REFS"
: > "$PARENTS"
: > "$HEAD_REF"
: > "$WORKTREES"
AUTHORS=$WORK/authors
: > "$AUTHORS"

# The address every commit is authored under unless author says otherwise.
ME=me@example.com

# author <commit> <email>
author() {
  printf '%s\t%s\n' "$1" "$2" >> "$AUTHORS"
}

author_of() {
  a=$(awk -F"$TAB" -v c="$1" '$1 == c { print $2 }' "$AUTHORS" | tail -1)
  printf '%s\n' "${a:-$ME}"
}

# worktree_for <ref> <path>: a branch someone is working in, which counts as
# live whether or not it was ever pushed.
worktree_for() {
  printf '%s\t%s\n' "$1" "$2" >> "$WORKTREES"
}

# A worktree's own git dir, the .git/worktrees/<name> git keeps for it. A real
# directory, because a lock is a file in it and the code under test reads it.
gitdir_of() {
  printf '%s/gitdirs/%s' "$WORK" "$(printf '%s' "$1" | tr '/' '_')"
}

# lock_worktree <path> [reason]: what `git worktree lock --reason` leaves, a
# file named locked holding the reason and a newline, or empty with no reason.
lock_worktree() {
  d=$(gitdir_of "$1")
  mkdir -p "$d"
  if [ -n "${2:-}" ]; then printf '%s\n' "$2" > "$d/locked"; else : > "$d/locked"; fi
}

# commit <id> [parent]
commit() {
  printf '%s\t%s\n' "$1" "${2:-}" >> "$PARENTS"
}

parent_of() {
  awk -F"$TAB" -v c="$1" '$1 == c { print $2; found = 1 } END { exit !found }' "$PARENTS"
}

# Every commit reachable from one, itself first, walking first parents.
ancestry() {
  c=$1
  while [ -n "$c" ]; do
    printf '%s\n' "$c"
    c=$(parent_of "$c" 2>/dev/null) || break
  done
}

reaches() {
  ancestry "$1" | grep -qxF "$2"
}

ref_set() {
  ref_del "$1"
  printf '%s\t%s\n' "$1" "$2" >> "$REFS"
}

ref_del() {
  grep -v "^$1$TAB" "$REFS" > "$REFS.new" 2>/dev/null || :
  mv "$REFS.new" "$REFS"
}

ref_of() {
  awk -F"$TAB" -v n="$1" '$1 == n { print $2; found = 1 } END { exit !found }' "$REFS"
}

resolve_ref() {
  case "$1" in
    refs/*) printf '%s' "$1"; return 0 ;;
  esac
  for prefix in refs/tags refs/heads refs/remotes; do
    ref_of "$prefix/$1" >/dev/null && { printf '%s' "$prefix/$1"; return 0; }
  done
  return 1
}

# A rev is a ref name or a commit id.
commit_of() {
  full=$(resolve_ref "$1") && { ref_of "$full"; return 0; }
  parent_of "$1" >/dev/null 2>&1 && { printf '%s' "$1"; return 0; }
  return 1
}

head_ref() {
  case "$1" in
    refs/*) printf '%s' "$1" ;;
    *) printf 'refs/heads/%s' "$1" ;;
  esac
}

refs() {
  sort "$REFS"
}

# Overridden by a case that needs a branch to have an upstream configured.
git_config_says() { return 1; }

replayed() {
  printf 'replayed-onto-%s-from-%s' "$1" "$2"
}

last_word() {
  all="$*"
  printf '%s' "${all##* }"
}

nth_word() {
  n=$1
  shift
  awk -v i="$n" '{ print $i }' <<EOF
$*
EOF
}

# Commits reachable from b but not from a, newest first, as git prints them.
range() {
  a=$(commit_of "$1") || a=''
  b=$(commit_of "$2") || return 1
  excluded=$(ancestry "$a")
  ancestry "$b" | while read -r c; do
    printf '%s\n' "$excluded" | grep -qxF "$c" && continue
    printf '%s\n' "$c"
  done
}

# The harness runs this in a subshell, so its names cannot reach the code under
# test.
git_says() (
  case "$*" in
    "rev-parse --verify --quiet "*)
      name=$(last_word "$@")
      # ref_of's status is the answer: resolve_ref only builds a name, and a
      # name that resolves to nothing must fail the way git fails.
      full=$(resolve_ref "$name") && { ref_of "$full"; return; }
      # <commit>^ is the parent, which is how a fork point is asked for.
      case "$name" in
        *^) parent_of "$(commit_of "${name%^}")" ;;
        *) return 1 ;;
      esac ;;
    "worktree add -q --detach "*|"worktree remove "*|"worktree prune")
      return 0 ;;
    "worktree list --porcelain")
      while IFS="$TAB" read -r ref path; do
        [ -n "$ref" ] || continue
        printf 'worktree %s\nbranch %s\n' "$path" "$ref"
        lock="$(gitdir_of "$path")/locked"
        if [ -s "$lock" ]; then printf 'locked %s\n' "$(cat "$lock")"
        elif [ -f "$lock" ]; then printf 'locked\n'; fi
        printf '\n'
      done < "$WORKTREES" ;;
    "-C "*" rev-parse --absolute-git-dir")
      d=$(gitdir_of "$(nth_word 2 "$@")")
      mkdir -p "$d"
      printf '%s\n' "$d" ;;
    # Every worktree is clean: nothing modified, untracked or ignored.
    "-C "*" status --porcelain"|"-C "*" status --porcelain --ignored"|"-C "*" status --porcelain -z")
      return 0 ;;
    "switch -q -c "*)
      new=$(head_ref "$(nth_word 4 "$@")")
      start=$(resolve_ref "$(nth_word 5 "$@")") || return 1
      ref_of "$new" >/dev/null && return 1
      base=$(ref_of "$start") || return 1
      ref_set "$new" "$base"
      printf '%s\n' "$new" > "$HEAD_REF"
      return 0 ;;
    "switch -q --detach")
      : > "$HEAD_REF"; return 0 ;;
    "rebase -q --onto "*)
      onto=$(nth_word 4 "$@")
      cur=$(cat "$HEAD_REF")
      [ -n "$cur" ] || return 1
      ref_set "$cur" "$(replayed "$onto" "$(ref_of "$cur")")"
      return 0 ;;
    "rebase --abort")
      return 0 ;;
    "branch -D "*|"branch -d "*)
      name=$(head_ref "$(last_word "$@")")
      ref_of "$name" >/dev/null || return 1
      ref_del "$name"
      return 0 ;;
    "for-each-ref --format=%(refname) refs/heads refs/remotes")
      cut -f1 "$REFS" | grep -E '^refs/(heads|remotes)/' ;;
    "for-each-ref --format=%(refname) refs/remotes")
      cut -f1 "$REFS" | grep -E '^refs/remotes/' ;;
    "for-each-ref --format=all %(refname) refs/remotes")
      cut -f1 "$REFS" | grep -E '^refs/remotes/' | sed 's/^/all /' ;;
    "for-each-ref --contains "*" --format=built %(refname) refs/heads refs/remotes")
      sha=$(commit_of "$(nth_word 3 "$@")") || return 1
      cut -f1 "$REFS" | grep -E '^refs/(heads|remotes)/' | while read -r r; do
        reaches "$(ref_of "$r")" "$sha" && printf 'built %s\n' "$r"
      done ;;
    "for-each-ref --contains "*" --format=holds %(refname) refs/heads refs/remotes")
      sha=$(commit_of "$(nth_word 3 "$@")") || return 1
      cut -f1 "$REFS" | grep -E '^refs/(heads|remotes)/' | while read -r r; do
        reaches "$(ref_of "$r")" "$sha" && printf 'holds %s\n' "$r"
      done ;;
    "for-each-ref --contains "*)
      sha=$(commit_of "$(nth_word 3 "$@")") || return 1
      short=no
      case "$*" in *'refname:short'*) short=yes ;; esac
      # Honour the namespaces asked for. Returning every ref regardless let a
      # test pass over a change that narrowed them.
      ns=''
      case "$*" in *' refs/heads'*) ns="$ns refs/heads/" ;; esac
      case "$*" in *' refs/remotes'*) ns="$ns refs/remotes/" ;; esac
      [ -n "$ns" ] || ns='refs/'
      cut -f1 "$REFS" | while read -r r; do
        in_ns=no
        for p in $ns; do
          case "$r" in "$p"*) in_ns=yes ;; esac
        done
        [ "$in_ns" = yes ] || continue
        reaches "$(ref_of "$r")" "$sha" || continue
        if [ "$short" = yes ]; then
          n=${r#refs/heads/}; n=${n#refs/remotes/}; printf '%s\n' "$n"
        else
          printf '%s\n' "$r"
        fi
      done ;;
    "-C "*" rev-list --merges --parents "*)
      return 0 ;;
    "config --get branch."*)
      key=$(last_word "$@")
      git_config_says "$key" || return 1
      # branch.<name>.remote answers origin; branch.<name>.merge answers the ref.
      case "$key" in
        *.remote) printf 'origin\n' ;;
        *.merge) printf 'refs/heads/%s\n' "$(printf '%s' "$key" | sed 's/^branch\.//; s/\.merge$//')" ;;
      esac ;;
    "for-each-ref --format=%(refname:short) refs/heads/"|"for-each-ref --format %(refname:short) refs/heads/")
      cut -f1 "$REFS" | sed -n 's@^refs/heads/@@p' ;;
    # The content of a change, named by its two ends. Two changes are the same
    # content only when they are the same change, so nothing is found in main
    # by content that is not in main by ancestry.
    "diff "*)
      printf 'change %s %s\n' "$(nth_word 2 "$@")" "$(nth_word 3 "$@")" ;;
    "log -1 --format=%cr "*)
      printf '5 days ago\n' ;;
    # A worktree's HEAD is the branch checked out in it.
    "-C "*" rev-list --count HEAD.."*)
      wt=$(nth_word 2 "$@")
      head=$(awk -F"$TAB" -v p="$wt" '$2 == p { print $1; exit }' "$WORKTREES")
      spec=$(last_word "$@")
      range "$head" "${spec#HEAD..}" | awk 'END { print NR }' ;;
    "-C "*" rev-parse --verify --quiet @{u}")
      return 1 ;;
    # No URL for origin, so no pull request host to ask.
    "config --get remote.origin.url")
      return 1 ;;
    "merge-base --is-ancestor "*)
      a=$(commit_of "$(nth_word 3 "$@")") || return 1
      b=$(commit_of "$(nth_word 4 "$@")") || return 1
      reaches "$b" "$a" ;;
    "merge-base "*)
      a=$(commit_of "$(nth_word 2 "$@")") || return 1
      b=$(commit_of "$(nth_word 3 "$@")") || return 1
      ancestry "$a" | while read -r c; do
        reaches "$b" "$c" && { printf '%s\n' "$c"; break; }
      done ;;
    "-C "*" config user.email")
      printf '%s\n' "$ME" ;;
    "log --format=%ae "*)
      spec=$(last_word "$@")
      range "${spec%%..*}" "${spec##*..}" | while read -r c; do author_of "$c"; done ;;
    "rev-list --count "*)
      spec=$(last_word "$@")
      # awk, not grep -c: grep exits non-zero on no matches, and a count of
      # zero is an answer, not a failure.
      range "${spec%%..*}" "${spec##*..}" | awk 'END { print NR }' ;;
    "rev-list "*" --not "*)
      spec=$(nth_word 2 "$@")
      excl=$(printf '%s' "$*" | sed 's/.* --not //')
      range "${spec%%..*}" "${spec##*..}" | while read -r c; do
        for e in $excl; do
          x=$(commit_of "$e") || continue
          reaches "$x" "$c" && { c=''; break; }
        done
        [ -n "$c" ] && printf '%s\n' "$c"
      done ;;
    "rev-list "*)
      spec=$(last_word "$@")
      range "${spec%%..*}" "${spec##*..}" ;;
    *)
      fail "the fake does not model: git $*" ;;
  esac
)
