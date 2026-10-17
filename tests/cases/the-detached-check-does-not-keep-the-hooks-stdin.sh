#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-vscode-wsl.sh
. "$TESTS/fake-vscode-wsl.sh"

describe "the detached check does not keep the hook's stdin"

# tmux's run-shell gives the job one socket as both stdin and stdout, and
# counts the job finished only once nothing holds it. The hook script moves
# stdout to its log but leaves stdin alone, so a copy that kept the hook's stdin
# would make tmux wait for the whole check, and for anything code leaves running.
# The setsid stand-in passes its stdin on, as util-linux's does.
WS=$WORK/weaver.code-workspace
FAKE_TITLES=''
cat > "$STANDINS/powershell.exe" <<'SHIM'
#!/bin/sh
echo check >> "$CHECK_LOG"
if IFS= read -r line; then printf '%s\n' "$line" > "$WORK/stdin-seen"; fi
exit 0
SHIM
chmod +x "$STANDINS/powershell.exe"
export WORK

printf 'from the hook\n' | run_first_call weaver "$WS"
wait_for "$CODE_LOG" || fail "the detached copy never ran code"
[ ! -e "$WORK/stdin-seen" ] || fail "the detached copy read the caller's stdin: $(cat "$WORK/stdin-seen")"
