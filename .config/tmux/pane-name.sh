#!/bin/sh
child=$(pgrep -P "$1" | head -1)
if [ -n "$child" ]; then
  comm=$(ps -o comm= -p "$child")
else
  comm=$(ps -o comm= -p "$1")
fi
echo "${comm##*/}"
