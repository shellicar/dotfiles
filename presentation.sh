#!/bin/sh
# The colours and icons the setup checks (setup/check-*.sh) print with.
# Sourced, never executed.
#
# The colours are the escape characters themselves, so a plain printf '%s'
# prints them. They are empty when stdout is not a terminal, so a log or a pipe
# gets no escape codes.
#
# The git commands in home/common/bin have their own set, in
# home/common/lib/git-common.sh, with the same colour codes stored as '\033'
# text for printf '%b' to expand. The two sets cannot stand in for each other:
# '%s' prints that text literally, and '%b' would also expand a backslash in
# the text around these.

# The names are defined here and read by the scripts that source this file,
# which shellcheck cannot see from inside it.
# shellcheck disable=SC2034

if [ -t 1 ]; then
  GREEN=$(printf '\033[0;32m'); YELLOW=$(printf '\033[1;33m'); RED=$(printf '\033[0;31m'); BLUE=$(printf '\033[0;34m')
  DIM=$(printf '\033[2m'); BOLD=$(printf '\033[1m'); RESET=$(printf '\033[0m')
else
  GREEN=''; YELLOW=''; RED=''; BLUE=''; DIM=''; BOLD=''; RESET=''
fi

OK='✅'; WARN='⚠️ '; QUESTION='❓'
