#!/bin/sh
#
# system.sh: show what on this machine is out of line with system/, and the
# commands that would bring it into line.
#
#   system.sh --plan   print the plan and change nothing; needs no root
#   system.sh -h       show this
#
# system/<feature>/ holds one feature's files at their real paths, and its
# platforms file names the OSes it is on for. Owner and mode are root:root, and
# 0755 or 0644 from git's executable bit, unless system/.gitattributes sets
# owner= or mode= for the path.
#
# The logic is in home/common/lib/system.sh, and its header describes the plan
# as data. This file is argument parsing and a call into it.

set -u

DIR=$(cd "$(dirname "$0")" && pwd)

# TODO(claude): undecided: the exit status for a wrong call. 64 (EX_USAGE)
# for now, where the commands in home/common/bin exit 2.
usage() {
  printf '%s\n' 'usage: system.sh --plan' >&2
  exit 64
}

PLAN=0
while [ $# -gt 0 ]; do
  case $1 in
    --plan) PLAN=1 ;;
    -h | --help) sed -n '3,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "system.sh: unknown option '$1'" >&2; usage ;;
  esac
  shift
done

# TODO(claude): the interactive list (#78) and --plan --apply (#77). Until
# they exist, only --plan runs.
if [ "$PLAN" -eq 0 ]; then
  echo "system.sh: only --plan exists so far" >&2
  usage
fi

# shellcheck source-path=SCRIPTDIR
# shellcheck source=home/common/lib/system.sh
. "$DIR/home/common/lib/system.sh"

SYS_REPO=$DIR
OS=$(sh "$DIR/get-os.sh") || exit 1
SYS_USER=$(id -un)

# TODO(claude): undecided: whether --plan's exit status says if anything is
# out of line. It exits 0 whenever the plan was worked out, for now.
system_plan_main
