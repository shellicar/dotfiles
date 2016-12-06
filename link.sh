#!/bin/sh

isdir() {
    [ -d "$1" ]
}

isfile() {
    [ -f "$1" ]
}

makelink() {
    if isfile "$1"; then
        printf "Linking file %s: " "$1"
        if ! isfile ../"$1"; then
            if ln -s "dotfiles/$1" "../$1"; then
                echo "ok!"
            fi
        elif [ "$(readlink "../$i")" = dotfiles/"$1" ]; then
            echo "exists"
        else
            echo "exists but not same"
        fi
    elif isdir "$1"; then
        printf "Linking dir %s: " "$1"
        if ! isdir "../$1"; then
            if ln -s "dotfiles/$1" "../$1"; then
                echo "ok!"
            fi
        elif [ "$(readlink "../$i")" = "dotfiles/$1" ]; then
            echo "exists"
        else
            echo "exists but not same"
        fi
    else
        echo "not file or directory: $1"
        exit 1
    fi
}

linkfiles() {
    for i in .*; do
        if ! isfile "$i"; then
            continue;
        fi

        makelink "$i"
    done
    unset i
}

linkdirs() {
    for i in *; do
        if ! isdir "$i"; then
            continue;
        fi

        makelink "$i"
    done
    unset i
}

linkfiles
linkdirs

