# A fake git: refs in a file, and the handful of operations these commands use,
# implemented against that model.
#
# It exists so a test can assert on state rather than on calls. Asserting that
# `git branch -D x` was issued pins the implementation; asserting that x is
# still there afterwards pins the behaviour, and survives the code being
# rewritten to reach the same end another way.
#
# Refs are held under their full names. A short name is resolved the way git
# resolves one, tags before heads, because that search order is the whole
# subject of several of these tests: a fake that mapped a short name straight to
# refs/heads would answer correctly where the real thing does not.

REFS=$WORK/refs
HEAD_REF=$WORK/head
: > "$REFS"
: > "$HEAD_REF"

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

# git-rev-parse's order for a name that is not already a full ref.
resolve_ref() {
  case "$1" in
    refs/*) printf '%s' "$1"; return 0 ;;
  esac
  for prefix in refs/tags refs/heads refs/remotes; do
    ref_of "$prefix/$1" >/dev/null && { printf '%s' "$prefix/$1"; return 0; }
  done
  return 1
}

# A new branch is always created under refs/heads, whatever it was cut from.
head_ref() {
  case "$1" in
    refs/*) printf '%s' "$1" ;;
    *) printf 'refs/heads/%s' "$1" ;;
  esac
}

refs() {
  sort "$REFS"
}

# A rebase produces different commits. The ids do not matter, but which base it
# replayed onto and what it replayed do, so both are visible in the result.
replayed() {
  printf 'replayed-onto-%s-from-%s' "$1" "$2"
}

# ${*##* } expands per positional parameter, not over the joined string, so the
# whole line comes back unchanged. Join first, then strip.
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

git_says() {
  case "$*" in
    "rev-parse --verify --quiet "*)
      name=$(last_word "$@")
      full=$(resolve_ref "$name") || return 1
      ref_of "$full" ;;
    "worktree add -q --detach "*|"worktree remove "*|"worktree prune")
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
    "for-each-ref --contains "*)
      sha=$(nth_word 3 "$@")
      awk -F"$TAB" -v s="$sha" '$2 == s { print $1 }' "$REFS" ;;
    *)
      fail "the fake does not model: git $*" ;;
  esac
}
