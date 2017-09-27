#!/bin/sh
for file in .bashrc .aliases .functions .path .dockerfunc; do
	if [ -f $file ]; then
		. "./$file"
	fi
done
unset file
