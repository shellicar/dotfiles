# bash: login shells. Bash reads only the first of .bash_profile, .bash_login
# and .profile, so this file exists to make that first one ours: anything else
# at ~/.bash_profile (a sandbox can leave an empty one) would skip .profile.
. "$HOME/.profile"
