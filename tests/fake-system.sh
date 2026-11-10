# Sourced by the system.sh cases, after harness.sh. Sources the library and
# stands in for the machine and the repo.
#
# The repo is a folder of features under $SYS_REPO/system, written by the case
# with feature and repo_file. The machine is a folder under $LIVE_ROOT, written
# with live_file, owned by whoever runs the tests; live_owner answers for it
# from FAKE_OWNERS instead, since a case cannot make a file root's. Mode is the
# file's real mode.
#
# git answers ls-files from the repo folder, every file tracked with the
# executable bit it has on disk, and check-attr from FAKE_ATTRS. A diff of two
# files is the real git's: it reads no repository.
#
#   FAKE_ATTRS   path TAB attr TAB value, one per line; path as git is given it
#                (system/<feature>/<path>); anything not listed is unspecified
#   FAKE_OWNERS  live path TAB owner:group, one per line; root:root otherwise
#   FAKE_SYSCTL  key=value, one per line; a key not listed cannot be read
#   FAKE_UNITS   unit TAB is-enabled TAB is-active, one per line
#   FAKE_BUS     up, or down for systemctl failing as it does without systemd
#   FAKE_BOOT    the kernel's boot time, and FAKE_MTIME every live file's
#                modification time, in seconds since the epoch

SYS_REPO=$WORK/repo
OS=wsl
SYS_USER=tester
mkdir -p "$SYS_REPO/system" "$WORK/root" "$WORK/tmp"
TMPDIR=$WORK/tmp
export TMPDIR

# shellcheck source=../home/common/lib/system.sh
. "$REPO/home/common/lib/system.sh"
LIVE_ROOT=$WORK/root

FAKE_ATTRS=''
FAKE_OWNERS=''
FAKE_SYSCTL=''
FAKE_UNITS=''
FAKE_BUS=up
FAKE_BOOT=1000
FAKE_MTIME=500

feature() { # <name> <platform>...
  local name
  name=$1
  shift
  mkdir -p "$SYS_REPO/system/$name"
  printf '%s\n' "$@" > "$SYS_REPO/system/$name/platforms"
}

repo_file() { # <feature> <path> <content> [executable]
  mkdir -p "$(dirname "$SYS_REPO/system/$1/$2")"
  printf '%s\n' "$3" > "$SYS_REPO/system/$1/$2"
  if [ "${4:-}" = executable ]; then chmod 0755 "$SYS_REPO/system/$1/$2"; else chmod 0644 "$SYS_REPO/system/$1/$2"; fi
}

live_file() { # <path> <content> [mode]
  mkdir -p "$(dirname "$LIVE_ROOT$1")"
  printf '%s\n' "$2" > "$LIVE_ROOT$1"
  chmod "${3:-0644}" "$LIVE_ROOT$1"
}

git_says() {
  [ "$1" = -C ] && shift 2
  case $1 in
    ls-files) fake_ls_files ;;
    check-attr) shift; fake_check_attr "$@" ;;
    --no-pager) command git "$@" ;;
    *) fail "the case did not say what git answers for: git $*" ;;
  esac
}

fake_ls_files() {
  (cd "$SYS_REPO" && find system \( -type f -o -type l \) | LC_ALL=C sort) | while IFS= read -r p; do
    if [ -L "$SYS_REPO/$p" ]; then m=120000
    elif [ -x "$SYS_REPO/$p" ]; then m=100755
    else m=100644
    fi
    printf '%s 0000000000000000000000000000000000000000 0\t%s\0' "$m" "$p"
  done
}

fake_check_attr() { # -z <attr>... -- <path>...
  local attrs p a v
  attrs=''
  [ "$1" = -z ] || fail "check-attr without -z: $*"
  shift
  while [ "$1" != -- ]; do attrs="$attrs $1"; shift; done
  shift
  for p in "$@"; do
    for a in $attrs; do
      v=$(printf '%s\n' "$FAKE_ATTRS" | awk -F"$SYS_TAB" -v p="$p" -v a="$a" '$1 == p && $2 == a { print $3; exit }')
      printf '%s\0%s\0%s\0' "$p" "$a" "${v:-unspecified}"
    done
  done
}

live_owner() { # <path>
  local o
  o=$(printf '%s\n' "$FAKE_OWNERS" | awk -F"$SYS_TAB" -v p="${1#"$LIVE_ROOT"}" '$1 == p { print $2; exit }')
  printf '%s\n' "${o:-root:root}"
}

# The file's real mode, read from ls rather than the library's GNU stat, so
# the cases run on macOS too. The real reader is run in tests/system.
live_mode() { # <path>
  # shellcheck disable=SC2012
  ls -ld -- "$1" | awk '
    function d(r, w, x,   n) {
      n = 0
      if (r == "r") n += 4
      if (w == "w") n += 2
      if (x ~ /[xst]/) n += 1
      return n
    }
    {
      p = $1; s = 0
      if (substr(p, 4, 1) ~ /[sS]/) s += 4
      if (substr(p, 7, 1) ~ /[sS]/) s += 2
      if (substr(p, 10, 1) ~ /[tT]/) s += 1
      printf "%d%d%d%d\n", s, d(substr(p, 2, 1), substr(p, 3, 1), substr(p, 4, 1)),
        d(substr(p, 5, 1), substr(p, 6, 1), substr(p, 7, 1)),
        d(substr(p, 8, 1), substr(p, 9, 1), substr(p, 10, 1))
    }'
}

mtime_epoch() { printf '%s\n' "$FAKE_MTIME"; }
boot_epoch() { printf '%s\n' "$FAKE_BOOT"; }

sysctl() { # -n <key>
  local v
  [ "$1" = -n ] || fail "sysctl asked something other than -n: $*"
  v=$(printf '%s\n' "$FAKE_SYSCTL" | awk -v k="$2" 'index($0, k "=") == 1 { print substr($0, length(k) + 2); exit }')
  if [ -z "$v" ]; then
    printf 'sysctl: cannot stat /proc/sys/%s: No such file or directory\n' "$2" >&2
    return 255
  fi
  printf '%s\n' "$v"
}

systemctl() { # is-enabled|is-active <unit>
  local row
  if [ "$FAKE_BUS" = down ]; then
    echo 'Failed to connect to bus: Operation not permitted' >&2
    return 1
  fi
  row=$(printf '%s\n' "$FAKE_UNITS" | awk -F"$SYS_TAB" -v u="$2" '$1 == u { print; exit }')
  [ -n "$row" ] || fail "the case did not say what systemctl answers for: systemctl $*"
  case $1 in
    is-enabled) printf '%s\n' "$row" | cut -f2 ;;
    is-active) printf '%s\n' "$row" | cut -f3 ;;
    *) fail "systemctl asked something the plan should not ask: systemctl $*" ;;
  esac
}

# Works out the plan into ROWS, in this shell, so a case can read it.
analyse() {
  system_features
  system_items
  system_tmp_open || fail "cannot make the temporary directory"
  system_analyse
}

# The row for a live path, and one field of it by name.
row_of() { # <path>
  printf '%s' "$ROWS" | awk -F"$SYS_TAB" -v p="$1" '$2 == p { print; exit }'
}

field() { # <path> <name>
  local n
  case $2 in
    feature) n=1 ;; path) n=2 ;; role) n=3 ;; state) n=4 ;; detail) n=5 ;;
    owner) n=6 ;; mode) n=7 ;; diff) n=8 ;; commands) n=9 ;; label) n=10 ;; restart) n=11 ;;
    *) fail "no field called $2" ;;
  esac
  row_of "$1" | cut -f"$n"
}

# The commands for a path, one per line.
commands_of() { # <path>
  field "$1" commands | tr "$SYS_US" '\n'
}

# The diff for a path, or nothing.
diff_of() { # <path>
  local d
  d=$(field "$1" diff)
  [ "$d" = - ] || cat "$d"
}
