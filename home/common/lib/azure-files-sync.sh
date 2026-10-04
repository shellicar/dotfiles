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

# Runs rclone, keeping its error output. Returns 0 on success, and 2, quietly,
# when rclone reports the path does not exist: exit 3 (directory not found) or
# 4 (file not found). Any other failure (sign-in, firewall, network, a file it
# cannot read) prints rclone's error and returns 1, so a caller stops rather
# than reading the file as absent.
rclone_read() {
  local err rc=0
  err=$(mktemp)
  rclone "$@" 2> "$err" || rc=$?
  case "$rc" in
    0) rm -f "$err"; return 0 ;;
    3|4) rm -f "$err"; return 2 ;;
  esac
  cat "$err" >&2
  rm -f "$err"
  echo "rclone $1 failed (exit $rc); stopping" >&2
  return 1
}

# MD5 of one file: the stored hash where there is one, computed by reading the
# file where there is not. Fails when rclone cannot read the file.
md5_of() {
  local out h rc=0
  out=$(rclone_read md5sum "$1") || rc=$?
  [ "$rc" = 2 ] && echo "not found: $1" >&2
  [ "$rc" = 0 ] || return 1
  h=$(printf '%s\n' "$out" | awk '{ print ($1 ~ /^[0-9a-f]+$/) ? $1 : ""; exit }')
  if [ -z "$h" ]; then
    out=$(rclone_read md5sum --download "$1") || return 1
    h=$(printf '%s\n' "$out" | awk '{ print $1; exit }')
  fi
  [ -n "$h" ] || { echo "no MD5 for $1" >&2; return 1; }
  printf '%s\n' "$h"
}

# "<size> bytes, modified <time>, MD5 <hash>", or "missing" when rclone reports
# the file does not exist. Fails on any other error.
describe() {
  local line size time hash rc=0
  line=$(rclone_read lsf --format st --separator "$(printf '\t')" "$1") || rc=$?
  [ "$rc" = 2 ] && { echo "missing"; return 0; }
  [ "$rc" = 0 ] || return 1
  [ -n "$line" ] || { echo "rclone listed nothing for $1" >&2; return 1; }
  size=${line%%$'\t'*}
  time=${line#*$'\t'}
  hash=$(md5_of "$1") || return 1
  printf '%s bytes, modified %s, MD5 %s\n' "$size" "$time" "$hash"
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
# downloaded to a temporary folder. A side that rclone reports as not existing
# reads as /dev/null to git; any other failure to read a side returns 1.
show_diff() {
  local local_file=$1 remote_file=$2 tmp copy a rc=0 ld rd
  tmp=$(mktemp -d)
  copy="$tmp/azure/$(basename "$local_file")"
  mkdir -p "$tmp/azure"
  rclone_read copyto "$remote_file" "$copy" || rc=$?
  case "$rc" in
    0) ;;
    2) copy=/dev/null ;;
    *) rm -rf "$tmp"; return 1 ;;
  esac
  a=$local_file
  [ -e "$a" ] || a=/dev/null
  rc=0
  if is_binary "$a" "$copy"; then
    if ld=$(describe "$local_file") && rd=$(describe "$remote_file"); then
      echo "binary"
      echo "  local: $ld"
      echo "  azure: $rd"
    else
      rc=1
    fi
  else
    # git diff exits 1 when the files differ, and above 1 on an error.
    git diff --no-index -- "$a" "$copy" || [ "$?" = 1 ] || rc=1
  fi
  rm -rf "$tmp"
  return "$rc"
}

# keep_side local|remote <local file> <remote file> <apply 0|1>
# Prints the direction and the difference; with apply=1, copies the kept side
# over the other.
# TODO(claude): undecided: whether keep-local / keep-remote refuse while
# bisync's lock for the folder exists. Built: they do not check it.
keep_side() {
  local side=$1 local_file=$2 remote_file=$3 apply=$4
  if [ "$side" = local ]; then
    echo "keep local: local → Azure"
  else
    echo "keep remote: Azure → local"
  fi
  echo "  local: $local_file"
  echo "  azure: $remote_file"
  show_diff "$local_file" "$remote_file" || { echo "stopped: nothing copied" >&2; return 1; }
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
  local local_dir=$1 remote=$2 tmp t path ls lt lh rs rt rh side rc
  t=$(printf '\t')
  tmp=$(mktemp -d)
  # A folder rclone reports as not existing lists as empty, as on a first sync
  # before the share path exists.
  for side in local remote; do
    rc=0
    if [ "$side" = local ]; then path=$local_dir; else path=$remote; fi
    rclone_read lsf -R --files-only --format psth --hash MD5 --separator "$t" \
      ${FILTERS[@]+"${FILTERS[@]}"} "$path" > "$tmp/$side" || rc=$?
    case "$rc" in
      0) ;;
      2) : > "$tmp/$side" ;;
      *) rm -rf "$tmp"; return 1 ;;
    esac
  done
  awk -F "$t" -v OFS="$t" '
    NR == FNR { s[$1] = $2; m[$1] = $3; h[$1] = $4; next }
    ($1 in s) { print $1, s[$1], m[$1], h[$1], $2, $3, $4 }
  ' "$tmp/local" "$tmp/remote" > "$tmp/both"
  while IFS="$t" read -r path ls lt lh rs rt rh; do
    if [ "$ls" = "$rs" ]; then
      [ -n "$lh" ] || lh=$(md5_of "$local_dir/$path" < /dev/null) || { rm -rf "$tmp"; return 1; }
      [ -n "$rh" ] || rh=$(md5_of "$(remote_join "$remote" "$path")" < /dev/null) || { rm -rf "$tmp"; return 1; }
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
#           one up, and both reach every machine. When the new name exists on
#           either side, or the rename fails, it is treated like a text file.
# Writes an rclone exclude line to <exclude file> for each file the resync must
# leave alone. Without apply nothing is renamed, and the binary ones are
# excluded too, so the dry run does not show them being overwritten.
resolve_resync_conflicts() {
  local local_dir=$1 remote=$2 apply=$3 excludes=$4
  local t path ls lt rs rt tmp copy host renamed taken rc
  t=$(printf '\t')
  host=$(hostname)
  : > "$excludes"
  tmp=$(mktemp -d)
  differing_files "$local_dir" "$remote" > "$tmp/differ" || { rm -rf "$tmp"; return 1; }
  while IFS="$t" read -r path ls lt rs rt; do
    copy="$tmp/remote"
    rclone_read copyto "$(remote_join "$remote" "$path")" "$copy" < /dev/null || { rm -rf "$tmp"; return 1; }
    if is_binary "$local_dir/$path" "$copy" < /dev/null; then
      renamed=$(host_name_for "$path" "$host")
      # The new name is taken when it exists on either side; Azure's side
      # counts as free only when rclone reports it not found.
      taken=0
      if [ -e "$local_dir/$renamed" ]; then
        taken=1
      else
        rc=0
        rclone_read lsf "$(remote_join "$remote" "$renamed")" > /dev/null < /dev/null || rc=$?
        case "$rc" in
          0) taken=1 ;;
          2) ;;
          *) rm -rf "$tmp"; return 1 ;;
        esac
      fi
      if [ "$taken" = 1 ]; then
        echo "binary file differs, and $renamed already exists, so it is left alone:"
        list_conflict "$local_dir" "$path" "$ls" "$lt" "$rs" "$rt"
        printf '/%s\n' "$(filter_escape "$path")" >> "$excludes"
      elif [ "$apply" = 1 ]; then
        if mv -- "$local_dir/$path" "$local_dir/$renamed"; then
          echo "binary file differs: kept both, local version renamed $path → $renamed"
        else
          echo "binary file differs, and it could not be renamed, so it is left alone:"
          list_conflict "$local_dir" "$path" "$ls" "$lt" "$rs" "$rt"
          printf '/%s\n' "$(filter_escape "$path")" >> "$excludes"
        fi
      else
        # TODO(claude): undecided: the dry run leaves a binary conflict out
        # of bisync's dry run, so bisync's listing does not show the renamed
        # copy going up or Azure's coming down that --apply will transfer.
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
# files, the newest of them, and of any .git/index git has written since,
# becomes .git/index and the rest are removed; the next sync carries that
# across.
resolve_git_index_conflicts() {
  local gitdir newest f
  find "$1" -type f -path '*/.git/index.conflict*' 2>/dev/null \
    | sed 's|/index\.conflict[^/]*$||' | sort -u \
    | while IFS= read -r gitdir; do
        set -- "$gitdir"/index.conflict*
        [ -e "$gitdir/index" ] && set -- "$gitdir/index" "$@"
        # shellcheck disable=SC2012
        newest=$(ls -t -- "$@" | head -n 1)
        for f in "$@"; do
          [ "$f" = "$newest" ] || rm -f -- "$f"
        done
        [ "$newest" = "$gitdir/index" ] || mv -f -- "$newest" "$gitdir/index"
        echo "$gitdir/index: kept the newest of $# copies ($(basename "$newest"))"
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
