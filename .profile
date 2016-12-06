for file in ~/.{aliases,functions,path}; do
	if [ -f $file ]; then
		source $file
	fi
done
unset file
