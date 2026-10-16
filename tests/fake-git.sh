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

# detached_worktree <commit> <path>: a worktree with no branch on it.
DETACHED_WORKTREES=$WORK/detached-worktrees
: > "$DETACHED_WORKTREES"
detached_worktree() {
  printf '%s\t%s\n' "$1" "$2" >> "$DETACHED_WORKTREES"
}

# lock_worktree <path> [reason]: `git worktree lock`, with or without --reason.
# The reason is held as the listing prints it.
LOCKS=$WORK/locks
: > "$LOCKS"
lock_worktree() {
  printf '%s\t%s\n' "$1" "${2:-}" >> "$LOCKS"
}

# The lines a locked worktree adds to its stanza in the listing: "locked
# <reason>", or "locked" alone when there is no reason.
lock_lines() {
  awk -F"$TAB" -v p="$1" '$1 == p { if ($2 == "") print "locked"; else print "locked " $2; exit }' "$LOCKS"
}

# lands <commit>: the commit's work reached the trunk under another commit, as a
# squash merge leaves it, so merging it into the trunk changes nothing. Only
# the commits a case names: a commit under one of them is not implied, because
# in a real repository it can fail once the trunk has changed the same lines.
LANDS=$WORK/lands
: > "$LANDS"
lands() {
  printf '%s\n' "$1" >> "$LANDS"
}

TIMES=$WORK/times
: > "$TIMES"

# The clock the fake reads, as git reads the system's: NOW when the case or the
# command under test has set it, the real time otherwise.
fake_now() {
  printf '%s\n' "${NOW:-$(date +%s)}"
}

# commit <id> [parent]: dated when it is made, as git dates one.
commit() {
  printf '%s\t%s\n' "$1" "${2:-}" >> "$PARENTS"
  printf '%s\t%s\n' "$1" "$(fake_now)" >> "$TIMES"
}

# committed <commit> <epoch>: gives the commit that committer time instead.
committed() {
  printf '%s\t%s\n' "$1" "$2" >> "$TIMES"
}

commit_time() {
  awk -F"$TAB" -v c="$1" '$1 == c { t = $2 } END { print t }' "$TIMES"
}

# How long ago <epoch> was at <now>, in git's wording for %cr (show_date_relative
# in git's date.c): each unit is rounded to the nearest before moving up to the
# next, and between one and five years the months are kept.
relative_date() {
  awk -v t="$1" -v now="$2" '
    function say(n, unit) { return n " " unit (n == 1 ? "" : "s") }
    BEGIN {
      if (now < t) { print "in the future"; exit }
      d = now - t
      if (d < 90) { print say(d, "second") " ago"; exit }
      d = int((d + 30) / 60)
      if (d < 90) { print say(d, "minute") " ago"; exit }
      d = int((d + 30) / 60)
      if (d < 36) { print say(d, "hour") " ago"; exit }
      d = int((d + 12) / 24)
      if (d < 14) { print say(d, "day") " ago"; exit }
      if (d < 70) { print say(int((d + 3) / 7), "week") " ago"; exit }
      if (d < 365) { print say(int((d + 15) / 30), "month") " ago"; exit }
      if (d < 1825) {
        m = int((d * 12 * 2 + 365) / (365 * 2))
        y = int(m / 12); m = m % 12
        if (m) print say(y, "year") ", " say(m, "month") " ago"
        else print say(y, "year") " ago"
        exit
      }
      print say(int((d + 183) / 365), "year") " ago"
    }'
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

# A tree id for a description, in hex as git prints one, since the library
# reads anything else from merge-tree as git failing.
tree_id() {
  printf '%s' "$1" | od -An -tx1 | tr -d ' \n'
  printf '\n'
}

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
    "rev-parse --verify --quiet "*"^{tree}")
      name=$(last_word "$@")
      c=$(commit_of "${name%^\{tree\}}") || return 1
      tree_id "tree $c" ;;
    "rev-parse --verify --quiet "*"^{commit}")
      name=$(last_word "$@")
      commit_of "${name%^\{commit\}}" ;;
    # The merged tree is the trunk's own when the commit is in it: by ancestry,
    # or because a case said its work landed there under another commit (a
    # squash). Anything else merges into a tree of its own.
    "merge-tree --write-tree "*)
      main=$(commit_of "$(nth_word 3 "$@")") || return 1
      c=$(commit_of "$(nth_word 4 "$@")") || return 1
      if reaches "$main" "$c" || grep -qxF "$c" "$LANDS"; then
        tree_id "tree $main"
      else
        tree_id "merging $c"
      fi ;;
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
        printf 'worktree %s\nHEAD %s\nbranch %s\n' "$path" "$(ref_of "$ref")" "$ref"
        lock_lines "$path"
        printf '\n'
      done < "$WORKTREES"
      while IFS="$TAB" read -r head path; do
        [ -n "$head" ] || continue
        printf 'worktree %s\nHEAD %s\ndetached\n' "$path" "$head"
        lock_lines "$path"
        printf '\n'
      done < "$DETACHED_WORKTREES" ;;
    # Every worktree is clean: nothing modified, untracked or ignored.
    "-C "*" status --porcelain"|"-C "*" status --porcelain --ignored"|"-C "*" status --porcelain -z --untracked-files=all")
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
      new=$(replayed "$onto" "$(ref_of "$cur")")
      # Dated when the rebase runs, as git dates the commits it replays.
      printf '%s\t%s\n' "$new" "$(fake_now)" >> "$TIMES"
      ref_set "$cur" "$new"
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
    # The tip's time, and how long before the fake's clock that was.
    "rev-list --no-commit-header -1 --format=%cr "*)
      c=$(commit_of "$(last_word "$@")") || return 128
      t=$(commit_time "$c")
      [ -n "$t" ] || fail "the fake made commit $c without a date: git $*"
      relative_date "$t" "$(fake_now)" ;;
    "rev-list --no-commit-header -1 --format=%ct "*)
      c=$(commit_of "$(last_word "$@")") || return 128
      t=$(commit_time "$c")
      [ -n "$t" ] || fail "the fake made commit $c without a date: git $*"
      printf '%s\n' "$t" ;;
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
      # No common commit fails, as git does for unrelated histories.
      base=$(ancestry "$a" | while read -r c; do
        reaches "$b" "$c" && { printf '%s\n' "$c"; break; }
      done)
      [ -n "$base" ] || return 1
      printf '%s\n' "$base" ;;
    "-C "*" config user.email")
      printf '%s\n' "$ME" ;;
    "rev-list --no-commit-header --format=%ae "*)
      spec=$(last_word "$@")
      range "${spec%%..*}" "${spec##*..}" | while read -r c; do author_of "$c"; done ;;
    # Tip first, as --topo-order gives it. The graph has first parents only, so
    # there are no merges and the walk down the ancestry is that order.
    "rev-list --topo-order -n "*)
      n=$(nth_word 4 "$@")
      spec=$(last_word "$@")
      range "${spec%%..*}" "${spec##*..}" | head -n "$n" ;;
    # The graph has no merges, so --no-merges leaves everything and --merges
    # finds nothing. The form is <tip> ^<base> ^<trunk>.
    "rev-list --count --no-merges "*)
      tip=$(nth_word 4 "$@"); b1=$(nth_word 5 "$@"); b2=$(nth_word 6 "$@")
      range "${b1#^}" "$tip" | while read -r c; do
        x=$(commit_of "${b2#^}") && reaches "$x" "$c" && continue
        printf '%s\n' "$c"
      done | awk 'END { print NR }' ;;
    "rev-list --merges "*)
      return 0 ;;
    # <a> ^<b>: commits reachable from a and not from b, the same set as b..a.
    # Either side naming nothing fails as git does, with 128. range() cannot be
    # left to do it: it reads an unknown excluded ref as excluding nothing.
    "rev-list --count "*" ^"*)
      [ $# -eq 4 ] || fail "the fake does not model: git $*"
      case "$3" in -*) fail "the fake does not model: git $*" ;; esac
      tip=$(commit_of "$3") || return 128
      exclude=$(commit_of "${4#^}") || return 128
      range "$exclude" "$tip" | awk 'END { print NR }' ;;
    # A last word with no .. is a form the fake does not model.
    "rev-list --count "*)
      spec=$(last_word "$@")
      case "$spec" in *..*) ;; *) fail "the fake does not model: git $*" ;; esac
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
