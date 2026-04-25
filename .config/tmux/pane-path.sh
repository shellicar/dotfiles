#!/bin/sh
DIR="${1:-$PWD}"
ORIGIN="$DIR"
while [ "$DIR" != "/" ]; do
  if [ -e "$DIR/.git" ]; then
    basename "$DIR"
    exit 0
  fi
  DIR="$(dirname "$DIR")"
done
basename "$ORIGIN"
