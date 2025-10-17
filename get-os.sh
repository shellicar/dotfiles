#!/bin/sh

# Returns: windows, wsl, macos, or linux
get_os() {
    if [ -n "$MSYSTEM" ]; then
        echo "windows-bash"
        return
    fi
    
    if [ -n "$WSL_DISTRO_NAME" ]; then
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
    echo "MSYSTEM: '$MSYSTEM'" >&2
    echo "WSL_DISTRO_NAME: '$WSL_DISTRO_NAME'" >&2
    echo "OSTYPE: '$OSTYPE'" >&2
    echo "uname -s: '$uname_result'" >&2
    exit 1
}

get_os
