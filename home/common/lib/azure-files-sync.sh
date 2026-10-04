#!/usr/bin/env bash
#
# azure-files-sync.sh: what ../bin/azure-files-sync does, as functions. Sourced,
# never executed. The command parses arguments and the config and calls these;
# tests/sync/run.sh calls them directly with two local folders standing in for
# a local folder and its Azure Files share.
#
# A "remote" here is any rclone path. In the command it is an on-the-fly
# Azure Files remote, ":azurefiles,share_name=<share>:<path>"; in the tests it
# is a plain local folder.
#
# WHAT THE CALLER OWES IT. Nothing runs at source time. The functions read:
#   WORKDIR  bisync's working folder: its listings and lock files. Passed to
#            bisync as --workdir, so the lock check and bisync agree on it.
#   FILTERS  array of rclone filter flags shared by every listing and sync, so
#            the conflict check sees exactly the files bisync does.
# Written for bash 3.2 (macOS): no associative arrays, no mapfile, and an array
# that may be empty is expanded as ${a[@]+"${a[@]}"} so `set -u` allows it.

# macOS writes ._* and .DS_Store metadata beside files; they mean nothing on
# the other machines. node_modules is left out at any depth, as a folder or a
# file. rclone never follows symlinks by default; --skip-links stops it
# printing a notice for each one.
default_filters() {
  FILTERS=(--exclude '._*' --exclude .DS_Store
           --exclude 'node_modules/**' --exclude node_modules
           --skip-links)
}

# bisync's default working folder: <rclone cache dir>/bisync.
default_workdir() {
  local cache
  cache=$(rclone config paths | sed -n 's/^Cache dir:[[:space:]]*//p')
  [ -n "$cache" ] || { echo "cannot read rclone's cache dir from 'rclone config paths'" >&2; return 1; }
  printf '%s/bisync\n' "$cache"
}

# Splits one SYNC entry, "local folder:share/path", at its last colon, so a
# Windows local folder (C:/Users/...) keeps its drive letter. Sets LOCAL_DIR,
# SHARE, SHARE_PATH (no leading slash) and REMOTE, which the command reads.
# shellcheck disable=SC2034
split_entry() {
  LOCAL_DIR=${1%:*}
  local spec=${1##*:}
  SHARE=${spec%%/*}
  SHARE_PATH=${spec#"$SHARE"}
  SHARE_PATH=${SHARE_PATH#/}
  # share_name is a backend setting, not part of the path, so each entry names
  # its share in an on-the-fly remote.
  REMOTE=":azurefiles,share_name=$SHARE:$SHARE_PATH"
}

# Appends a relative path to a remote: "x:" + "a/b" is "x:a/b", "x:p" is "x:p/a/b".
remote_join() {
  case "$1" in
    *:) printf '%s%s\n' "$1" "$2" ;;
    *)  printf '%s/%s\n' "$1" "$2" ;;
  esac
}

# ── locks ───────────────────────────────────────────────────────────────────
#
# bisync names its state files after both paths: <workdir>/<session>.path1.lst,
# and the lock <workdir>/<session>.lck. The session name is built as rclone's
# cmd/bisync/bilib/canonical.go builds it (SessionName): each side's path, with
# a trailing slash, trimmed of slashes at both ends, every whitespace \ / : ? *
# replaced with _, and the first {...} removed. A remote side reads as
# "<name>:<root>", and an on-the-fly remote's name is ":<backend>" plus a {hex}
# suffix that the last step removes. The share name is not part of it.
# A local folder reads as plain "<path>" only while no local-backend option is
# overridden. --skip-links is one, so in FILTERS it makes the local side
# "local{hex}:<path>", and so "local:<path>" once the {hex} is removed.

canonical_path() {
  local s=$1 pre post open close
  while :; do
    case "$s" in
      [\\/]*) s=${s#?} ;;
      *[\\/]) s=${s%?} ;;
      *) break ;;
    esac
  done
  s=$(printf '%s' "$s" | sed 's/[[:space:]\\/:?*]/_/g')
  pre=${s%%\{*}
  post=${s#*\}}
  open=${#pre}
  close=$(( ${#s} - ${#post} - 1 ))
  if [ "$pre" != "$s" ] && [ "$post" != "$s" ] && [ "$close" -gt "$open" ]; then
    s=$pre$post
  fi
  printf '%s\n' "$s"
}

# The path rclone reports for one side of a bisync, with --skip-links set.
fs_path() {
  local p=$1 backend
  case "$p" in
    :*)
      p=${p#:}
      backend=${p%%[,:]*}
      p=":$backend:${p#*:}" ;;
    /*|[A-Za-z]:*) p="local:$p" ;;
    *) p="local:$(pwd)/$p" ;;
  esac
  case "$p" in */) ;; *) p="$p/" ;; esac
  printf '%s\n' "$p"
}

lock_file() {
  printf '%s/%s..%s.lck\n' "$WORKDIR" \
    "$(canonical_path "$(fs_path "$1")")" "$(canonical_path "$(fs_path "$2")")"
}

# Refuses (returns 1) when bisync's lock for this pair exists. bisync writes its
# PID into the lock, first as the bare number and then as JSON ("PID":"1234").
# A lock is never removed here and never treated as expired.
check_lock() {
  local lock pid
  lock=$(lock_file "$1" "$2")
  [ -e "$lock" ] || return 0
  pid=$(sed -n 's/.*"PID":"\([0-9]*\)".*/\1/p' "$lock")
  [ -n "$pid" ] || pid=$(sed -n 's/^\([0-9][0-9]*\)$/\1/p' "$lock" | head -n 1)
  # TODO(claude): undecided: under Git Bash on Windows, ps lists MSYS process
  # IDs, and rclone.exe writes its Windows PID, so a running sync may read as
  # gone. Unverified; ps -p is used everywhere for now.
  if [ -n "$pid" ] && ps -p "$pid" >/dev/null 2>&1; then
    echo "refused: a sync of this folder is already running (process $pid, lock $lock)" >&2
  else
    echo "refused: bisync's lock for this folder is left from a run that is no longer running${pid:+ (process $pid)}." >&2
    echo "Once nothing is syncing this folder, delete the lock with:" >&2
    printf '  rm %q\n' "$lock" >&2
  fi
  return 1
}

# ── comparing one file ──────────────────────────────────────────────────────

# MD5 of one file: the stored hash where there is one, computed by reading the
# file where there is not.
md5_of() {
  local h
  h=$(rclone md5sum "$1" 2>/dev/null | awk '{ print ($1 ~ /^[0-9a-f]+$/) ? $1 : ""; exit }')
  [ -n "$h" ] || h=$(rclone md5sum --download "$1" | awk '{ print $1; exit }')
  printf '%s\n' "$h"
}

# "<size> bytes, modified <time>, MD5 <hash>", or "missing".
describe() {
  local line size time
  line=$(rclone lsf --format st --separator "$(printf '\t')" "$1" 2>/dev/null) || line=
  [ -n "$line" ] || { echo "missing"; return 0; }
  size=${line%%$'\t'*}
  time=${line#*$'\t'}
  printf '%s bytes, modified %s, MD5 %s\n' "$size" "$time" "$(md5_of "$1")"
}

# Binary is what git diff calls binary: --numstat prints "-<tab>-" for it.
is_binary() {
  local stat
  stat=$(git diff --no-index --numstat -- "$1" "$2" 2>/dev/null) || :
  case "$stat" in -$'\t'-$'\t'*) return 0 ;; esac
  return 1
}

# Shows how a local file and its remote copy differ: git's diff for text, or
# "binary" and each side's size, modified time and MD5. The remote copy is
# downloaded to a temporary folder; a side that does not exist reads as
# /dev/null to git.
show_diff() {
  local local_file=$1 remote_file=$2 tmp copy a
  tmp=$(mktemp -d)
  copy="$tmp/azure/$(basename "$local_file")"
  mkdir -p "$tmp/azure"
  rclone copyto "$remote_file" "$copy" 2>/dev/null || copy=/dev/null
  a=$local_file
  [ -e "$a" ] || a=/dev/null
  if is_binary "$a" "$copy"; then
    echo "binary"
    echo "  local: $(describe "$local_file")"
    echo "  azure: $(describe "$remote_file")"
  else
    git diff --no-index -- "$a" "$copy" || :
  fi
  rm -rf "$tmp"
}

# keep_side local|remote <local file> <remote file> <apply 0|1>
# Prints the direction and the difference; with apply=1, copies the kept side
# over the other.
keep_side() {
  local side=$1 local_file=$2 remote_file=$3 apply=$4
  if [ "$side" = local ]; then
    echo "keep local: local → Azure"
  else
    echo "keep remote: Azure → local"
  fi
  echo "  local: $local_file"
  echo "  azure: $remote_file"
  show_diff "$local_file" "$remote_file"
  if [ "$apply" != 1 ]; then
    echo "dry run: re-run with --apply to copy"
    return 0
  fi
  # --ignore-times copies even when size and modified time already match,
  # which they can when only the content differs.
  if [ "$side" = local ]; then
    rclone copyto --ignore-times "$local_file" "$remote_file"
  else
    rclone copyto --ignore-times "$remote_file" "$local_file"
  fi
}

# ── resync conflicts ────────────────────────────────────────────────────────

# Lists each file on both sides whose content differs, one per line:
#   path<TAB>local size<TAB>local time<TAB>remote size<TAB>remote time
# Sizes that differ settle it. Equal sizes are compared by MD5: the stored one,
# or one computed for a side that has none stored. Equal MD5s are the same
# content, whatever the modified times say.
differing_files() {
  local local_dir=$1 remote=$2 tmp t path ls lt lh rs rt rh
  t=$(printf '\t')
  tmp=$(mktemp -d)
  rclone lsf -R --files-only --format psth --hash MD5 --separator "$t" \
    ${FILTERS[@]+"${FILTERS[@]}"} "$local_dir" > "$tmp/local" || { rm -rf "$tmp"; return 1; }
  rclone lsf -R --files-only --format psth --hash MD5 --separator "$t" \
    ${FILTERS[@]+"${FILTERS[@]}"} "$remote" > "$tmp/remote" || { rm -rf "$tmp"; return 1; }
  awk -F "$t" -v OFS="$t" '
    NR == FNR { s[$1] = $2; m[$1] = $3; h[$1] = $4; next }
    ($1 in s) { print $1, s[$1], m[$1], h[$1], $2, $3, $4 }
  ' "$tmp/local" "$tmp/remote" > "$tmp/both"
  while IFS="$t" read -r path ls lt lh rs rt rh; do
    if [ "$ls" = "$rs" ]; then
      [ -n "$lh" ] || lh=$(md5_of "$local_dir/$path" < /dev/null)
      [ -n "$rh" ] || rh=$(md5_of "$(remote_join "$remote" "$path")" < /dev/null)
      [ "$lh" = "$rh" ] && continue
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$path" "$ls" "$lt" "$rs" "$rt"
  done < "$tmp/both"
  rm -rf "$tmp"
}

# The name a binary file's local version takes when both versions are kept:
# name-<host>.ext.
# TODO(claude): undecided: the name for a file with no extension, a dotfile,
# or a name with several dots. Built: "-<host>" goes before the last dot that
# is not the first character, else at the end (README-host, .bashrc-host,
# archive.tar-host.gz).
host_name_for() {
  local path=$1 host=$2 dir base stem ext
  dir=$(dirname "$path")
  base=$(basename "$path")
  stem=${base%.*}
  if [ -n "$stem" ] && [ "$stem" != "$base" ]; then
    ext=${base##*.}
    base="$stem-$host.$ext"
  else
    base="$base-$host"
  fi
  if [ "$dir" = . ]; then printf '%s\n' "$base"; else printf '%s/%s\n' "$dir" "$base"; fi
}

# Escapes a path for an rclone filter line.
filter_escape() {
  printf '%s\n' "$1" | sed 's/[][\\*?{}]/\\&/g'
}

# resolve_resync_conflicts <local dir> <remote> <apply 0|1> <exclude file>
# For each file that differs on the two sides:
#   text:   left as it is on both sides, listed with the commands that show the
#           difference and pick a side;
#   binary: the local version is renamed name-<host>.ext, so the resync brings
#           Azure's version down under the original name and sends the renamed
#           one up, and both reach every machine.
# Writes an rclone exclude line to <exclude file> for each file the resync must
# leave alone. Without apply nothing is renamed, and the binary ones are
# excluded too, so the dry run does not show them being overwritten.
resolve_resync_conflicts() {
  local local_dir=$1 remote=$2 apply=$3 excludes=$4
  local t path ls lt rs rt tmp copy host renamed
  t=$(printf '\t')
  host=$(hostname)
  : > "$excludes"
  tmp=$(mktemp -d)
  differing_files "$local_dir" "$remote" > "$tmp/differ" || { rm -rf "$tmp"; return 1; }
  while IFS="$t" read -r path ls lt rs rt; do
    copy="$tmp/remote"
    rclone copyto "$(remote_join "$remote" "$path")" "$copy" < /dev/null
    if is_binary "$local_dir/$path" "$copy" < /dev/null; then
      renamed=$(host_name_for "$path" "$host")
      if [ -e "$local_dir/$renamed" ]; then
        # TODO(claude): undecided: what happens when name-<host>.ext already
        # exists. Built: the file is left alone and listed like a text file.
        echo "binary file differs, and $renamed already exists, so it is left alone:"
        list_conflict "$local_dir" "$path" "$ls" "$lt" "$rs" "$rt"
        printf '/%s\n' "$(filter_escape "$path")" >> "$excludes"
      elif [ "$apply" = 1 ]; then
        mv -- "$local_dir/$path" "$local_dir/$renamed"
        echo "binary file differs: kept both, local version renamed $path → $renamed"
      else
        echo "binary file differs: would rename the local version $path → $renamed and keep both"
        printf '/%s\n' "$(filter_escape "$path")" >> "$excludes"
      fi
    else
      echo "text file differs, left alone on both sides:"
      list_conflict "$local_dir" "$path" "$ls" "$lt" "$rs" "$rt"
      printf '/%s\n' "$(filter_escape "$path")" >> "$excludes"
    fi
  done < "$tmp/differ"
  rm -rf "$tmp"
}

list_conflict() {
  local file="$1/$2"
  printf '  %s\n' "$file"
  printf '    local: %s bytes, modified %s\n' "$3" "$4"
  printf '    azure: %s bytes, modified %s\n' "$5" "$6"
  printf '    azure-files-sync diff %q\n' "$file"
  printf '    azure-files-sync keep-local %q\n' "$file"
  printf '    azure-files-sync keep-remote %q\n' "$file"
}

# ── after a sync ────────────────────────────────────────────────────────────

# When both sides changed a .git/index, bisync keeps both as index.conflict1
# and index.conflict2 and git sees no index. In each .git folder holding such
# files, the newest becomes .git/index and the rest are removed; the next sync
# carries that across.
# TODO(claude): undecided: a .git/index that already exists beside the
# conflict copies is replaced by the newest copy, not compared with them.
resolve_git_index_conflicts() {
  local gitdir newest f
  find "$1" -type f -path '*/.git/index.conflict*' 2>/dev/null \
    | sed 's|/index\.conflict[^/]*$||' | sort -u \
    | while IFS= read -r gitdir; do
        # shellcheck disable=SC2012
        newest=$(ls -t "$gitdir"/index.conflict* | head -n 1)
        for f in "$gitdir"/index.conflict*; do
          [ "$f" = "$newest" ] || rm -f -- "$f"
        done
        mv -f -- "$newest" "$gitdir/index"
        echo "$gitdir/index: kept the newest of the conflicting copies"
      done
}

# ── one folder ──────────────────────────────────────────────────────────────

# sync_folder <local dir> <remote> <apply> <resync> <force>
sync_folder() {
  local local_dir=$1 remote=$2 apply=$3 resync=$4 force=$5 excludes status=0
  local flags=(--resilient --recover --create-empty-src-dirs --max-delete 75
               --workdir "$WORKDIR")
  flags+=(${FILTERS[@]+"${FILTERS[@]}"})
  [ "$force" = 1 ] && flags+=(--force)
  [ "$apply" = 1 ] || flags+=(--dry-run)

  check_lock "$local_dir" "$remote" || return 1

  excludes=$(mktemp)
  if [ "$resync" = 1 ]; then
    resolve_resync_conflicts "$local_dir" "$remote" "$apply" "$excludes" || { rm -f "$excludes"; return 1; }
    flags+=(--resync --exclude-from "$excludes")
  fi

  rclone bisync "$local_dir" "$remote" "${flags[@]}" || status=$?
  rm -f "$excludes"

  [ "$apply" = 1 ] && resolve_git_index_conflicts "$local_dir"
  return "$status"
}
