#!/bin/sh

for file in ~/.{aliases,functions,path,sshagent,dockerfunc}; do
	if [ -f $file ]; then
		source $file
	fi
done
unset file
