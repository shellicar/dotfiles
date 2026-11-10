# Sourced by a case, inside the container, as root.
#
# A copy of the repo at /work/repo holding the real system.sh, its library,
# get-os.sh and system/.gitattributes, and whatever features the case writes
# with feature and repo_file; repo_done puts it in a git index, so git's
# executable bit and check-attr are the real git's. The machine is the
# container's own /etc and /usr/local. The command runs as tester.

R=/work/repo
mkdir -p "$R/home/common/lib" "$R/system" /work/tmp
chmod 1777 /work/tmp
cp /repo/system.sh /repo/get-os.sh "$R/"
cp /repo/home/common/lib/system.sh "$R/home/common/lib/"
cp /repo/system/.gitattributes "$R/system/"

fail() { printf 'FAIL %s\n' "$1" >&2; exit 1; }
ok() { printf '  ok   %s\n' "$1"; }

# A feature on for every OS get-os.sh can report inside a container.
feature() { # <name>
  mkdir -p "$R/system/$1"
  printf 'wsl\nlinux\n' > "$R/system/$1/platforms"
}

repo_file() { # <feature> <path> <content> [executable]
  mkdir -p "$(dirname "$R/system/$1/$2")"
  printf '%s\n' "$3" > "$R/system/$1/$2"
  [ "${4:-}" = executable ] && chmod 0755 "$R/system/$1/$2"
  return 0
}

repo_done() {
  (cd "$R" && git init -q && git add -A) || fail "cannot make the repo's index"
}

# A file on the machine, owned and moded as given.
live_file() { # <path> <content> <owner:group> <mode>
  mkdir -p "$(dirname "$1")"
  printf '%s\n' "$2" > "$1"
  chown "$3" "$1"
  chmod "$4" "$1"
}

# Owner, mode, size, time and checksum of each path given, or that it is
# absent, so a case can show the command changed none of them.
fingerprint() { # <path>...
  for p in "$@"; do
    if [ -e "$p" ]; then
      printf '%s %s\n' "$(stat -c '%U:%G %a %s %Y' "$p")" "$(cksum < "$p")"
    else
      printf 'absent %s\n' "$p"
    fi
  done
}

# Runs system.sh --plan as tester, showing what it printed, indented; the
# output is left in /work/out.
plan() {
  printf -- '--- system.sh --plan ---\n'
  runuser -u tester -- env TMPDIR=/work/tmp "$R/system.sh" --plan > /work/out 2>&1
  status=$?
  sed 's/^/  | /' /work/out
  return "$status"
}

has() { # <text> <what>
  grep -qF -- "$1" /work/out || fail "$2: expected the output to contain: $1"
  ok "$2"
}
