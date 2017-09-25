#!/bin/sh
for file in .bashrc .aliases .functions .path .sshagent .dockerfunc; do
	if [ -f $file ]; then
		. "$file"
	fi
done
unset file
