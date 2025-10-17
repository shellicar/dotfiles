#!/bin/sh
set -e

DOTFILES_SETTINGS="$HOME/dotfiles/.vscode/settings.json"
DRY_RUN=1

while [ $# -gt 0 ]; do
    case "$1" in
        -d|--destructive)
            DRY_RUN=0
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [-d|--destructive]"
            echo "  -d, --destructive    Actually write changes (default is dry-run)"
            echo "  -h, --help          Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Use -h for help" >&2
            exit 1
            ;;
    esac
done

if [ ! -f "$DOTFILES_SETTINGS" ]; then
    echo "Error: Central settings file not found at $DOTFILES_SETTINGS"
    exit 1
fi

detect_vscode_settings_path() {
    os=$(../get-os.sh)
    
    case "$os" in
        windows-bash)
            echo "Detected: Windows Git Bash" >&2
            echo "/c/Users/$(whoami)/AppData/Roaming/Code/User/settings.json"
            ;;
        wsl)
            echo "Detected: WSL" >&2
            echo "/mnt/c/Users/$(whoami)/AppData/Roaming/Code/User/settings.json"
            ;;
        macos)
            echo "Detected: macOS" >&2
            echo "$HOME/Library/Application Support/Code/User/settings.json"
            ;;
        linux)
            echo "Error: Native Linux not supported" >&2
            exit 1
            ;;
        *)
            echo "Error: Unsupported OS: $detected_os" >&2
            exit 1
            ;;
    esac
}

merge_settings() {
    central_file="$1"
    target_file="$2"
    backup_file="$3"
    
    if [ ! -f "$target_file" ]; then
        echo "Target file does not exist - will be created"
    else
        echo "Target file exists - merging settings"
    fi
    
    merged_content=$(node "./merge-vscode-settings.js" "$central_file" "$target_file")
    
    if [ $? -eq 0 ] && [ -n "$merged_content" ]; then
        if [ -f "$target_file" ]; then
            target_diff="$target_file"
        else
            target_diff="/dev/null"
        fi
        diff_output=$(echo "$merged_content" | diff "$target_diff" - 2>/dev/null || true)
        
        if [ -z "$diff_output" ]; then
            echo "No changes needed - settings are already up to date"
            return
        fi
        
        echo "Changes that would be made:"
        echo "$diff_output"
        
        if [ $DRY_RUN -eq 1 ]; then
            echo "[DRY RUN] Use -d to actually write these changes."
        else
            if [ -f "$target_file" ]; then
                cp "$target_file" "$backup_file"
                echo "Backup created: $backup_file"
            fi
            echo "$merged_content" > "$target_file"
            echo "Settings merged successfully: $target_file"
        fi
    else
        echo "Error: Failed to merge settings" >&2
        exit 1
    fi
}

main() {
    echo "Central settings: $DOTFILES_SETTINGS"
    
    target_path=$(detect_vscode_settings_path)
    backup_path="${target_path}.backup.$(date +%Y%m%d_%H%M%S)"
    
    echo "Target settings: $target_path"
    
    target_dir=$(dirname "$target_path")
    mkdir -p "$target_dir"
    
    merge_settings "$DOTFILES_SETTINGS" "$target_path" "$backup_path"
    
    echo "✅ VS Code settings sync complete!"
}

main "$@"
