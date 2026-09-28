#!/bin/sh
# Colours and icons to print with. Sourced, never executed.
#
# The colours are the escape characters themselves, for printf '%s'.
# home/common/lib/git-common.sh has its own set, stored as '\033' text for
# printf '%b'. The two cannot stand in for each other: '%s' prints that text
# literally, and '%b' would also expand a backslash in the text around these.

# Read where this is sourced, which shellcheck cannot see from here.
# shellcheck disable=SC2034

if [ -t 1 ]; then
  GREEN=$(printf '\033[0;32m'); YELLOW=$(printf '\033[1;33m'); RED=$(printf '\033[0;31m'); BLUE=$(printf '\033[0;34m')
  DIM=$(printf '\033[2m'); BOLD=$(printf '\033[1m'); RESET=$(printf '\033[0m')
else
  GREEN=''; YELLOW=''; RED=''; BLUE=''; DIM=''; BOLD=''; RESET=''
fi

OK='✅'; WARN='⚠️ '; QUESTION='❓'
