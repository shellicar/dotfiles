for file in ~/.{aliases,functions,path,sshagent}; do
	if [ -f $file ]; then
		source $file
	fi
done
unset file
