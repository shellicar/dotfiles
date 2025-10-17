#!/bin/sh

isdir() {
    [ -d "$1" ]
}

isfile() {
    [ -f "$1" ]
}

link_item() {
    source="$1"
    target="$2"
    
    printf "Linking file %s: " "$target"
    if ! isfile "../$target"; then
        if ln -s "dotfiles/$source" "../$target"; then
            echo "ok!"
        fi
    elif [ "$(readlink "../$target")" = "dotfiles/$source" ]; then
        echo "exists (symlink)"
    elif diff -q "$source" "../$target" >/dev/null 2>&1; then
        echo "exists (content same)"
    else
        echo "exists but not same"
    fi
}

makelink() {
    if isfile "$1"; then
        link_item "$1" "$1"
    elif isdir "$1"; then
        printf "Linking dir %s: " "$1"
        if ! isdir "../$1"; then
            if ln -s "dotfiles/$1" "../$1"; then
                echo "ok!"
            fi
        elif [ "$(readlink "../$1")" = "dotfiles/$1" ]; then
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

        case "$i" in
            .gitconfig-*)
                continue
                ;;
        esac

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

os=$(./get-os.sh)

case "$os" in
    macos)
        link_item ".gitconfig-macos" ".gitconfig"
        ;;
    windows-bash|wsl|linux)
        link_item ".gitconfig-linux" ".gitconfig"
        ;;
    *)
        echo "Error: Unsupported OS: $os"
        exit 1
        ;;
esac

