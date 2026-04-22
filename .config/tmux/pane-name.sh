#!/bin/sh
child=$(pgrep -P "$1" | head -1)
if [ -n "$child" ]; then
  ps -o comm= -p "$child"
else
  ps -o comm= -p "$1"
fi
