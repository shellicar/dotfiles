#!/bin/sh
# The colours and icons setup and install print with. Sourced, never executed.
# The git commands in home/common/bin have their own, in
# home/common/lib/git-common.sh, and these use the same codes and glyphs.
#
# The colours are the escape characters themselves, not '\033' text, so a plain
# printf '%s' prints them. They are empty when stdout is not a terminal, so a
# log or a pipe gets no escape codes.

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
