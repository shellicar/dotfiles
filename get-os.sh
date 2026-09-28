#!/bin/sh

# Returns: wsl, macos, or linux
get_os() {
    # WSL2's kernel is "...-microsoft-standard-WSL2", WSL1's "...-Microsoft".
    # Not WSL_DISTRO_NAME: ssh, cron, sudo and systemd sessions lack it.
    if grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
        echo "wsl"
        return
    fi
    
    if [ -n "$OSTYPE" ] && [ "${OSTYPE#darwin}" != "$OSTYPE" ]; then
        echo "macos"
        return
    fi
    
    uname_result=$(uname -s)
    if [ "$uname_result" = "Linux" ]; then
        echo "linux"
        return
    fi
    
    echo "Error: Unable to detect OS" >&2
    echo "kernel osrelease: '$(cat /proc/sys/kernel/osrelease 2>/dev/null)'" >&2
    echo "OSTYPE: '$OSTYPE'" >&2
    echo "uname -s: '$uname_result'" >&2
    exit 1
}

get_os
