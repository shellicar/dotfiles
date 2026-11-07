#!/bin/sh
# .local/bin/tmux-last-pane, the script behind Tab, run as run-shell runs it: as
# a program, by its path. It goes to the most recent pane in @pane-history that
# still exists and is not the current one, writes the history back without the
# closed panes, and with nowhere to go shows a message. On every path it prints
# nothing and exits 0, because run-shell covers the pane with either.
#
# Ids are matched whole: %1 closed must not take %12 with it, nor the reverse.
# How the focus hook treats them is a claim about tmux formats, so it is in
# tests/tmux instead.
#
# The script is a child process, where the harness's tmux function cannot
# follow, so tmux here is a small program on PATH backed by state files: the
# history (absent means unset), the panes that exist, the pane the client is
# on, and the message shown. It fails the way tmux does, with a line on stderr,
# for a switch to a missing pane and for the failure flags below.
# TODO(claude): undecided: whether the script is tested as a program with this
# fake on PATH, or split into a sourced library so tests/fake-tmux.sh and the
# harness's tmux function can answer it, as tmux-snapshot's cases do. A program
# for now, which is also how run-shell runs it.
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"

describe 'Tab goes back to the most recent pane that still exists'

SCRIPT=$REPO/.local/bin/tmux-last-pane
FAKE_TMUX_STATE=$WORK/state
export FAKE_TMUX_STATE

mkdir -p "$WORK/bin"
cat > "$WORK/bin/tmux" <<'FAKE'
#!/bin/sh
S=$FAKE_TMUX_STATE
printf '%s\n' "$*" >> "$S/calls"
case "$*" in
  'show-options -gqv @pane-history')
    [ -f "$S/history" ] && { cat "$S/history"; echo; }
    exit 0 ;;
  'list-panes -a -F #{pane_id}')
    cat "$S/panes" || exit 1
    exit 0 ;;
  'set-option -g @pane-history '*)
    [ -f "$S/fail-set" ] && { echo 'command too long' >&2; exit 1; }
    printf '%s' "$4" > "$S/history"
    exit 0 ;;
  'switch-client -t '*)
    if [ -f "$S/fail-switch" ] || ! grep -qxF -- "$3" "$S/panes"; then
      echo "can't find pane: $3" >&2
      exit 1
    fi
    printf '%s' "$3" > "$S/client"
    exit 0 ;;
  'display-message '*)
    printf '%s' "$2" > "$S/message"
    exit 0 ;;
esac
echo "fake tmux: unexpected: $*" >&2
: > "$S/unexpected"
exit 1
FAKE
chmod +x "$WORK/bin/tmux"
PATH=$WORK/bin:$PATH
export PATH

# given <history, or UNSET> <pane>...: a fresh server with these panes.
given() {
  rm -rf "$FAKE_TMUX_STATE"
  mkdir -p "$FAKE_TMUX_STATE"
  [ "$1" = UNSET ] || printf '%s' "$1" > "$FAKE_TMUX_STATE/history"
  shift
  printf '%s\n' "$@" > "$FAKE_TMUX_STATE/panes"
}

state() { # <name>: a state file's content, or nothing
  cat "$FAKE_TMUX_STATE/$1" 2>/dev/null
}

# tab <current pane> <what>: presses Tab and checks it printed nothing, exited
# 0 and asked tmux only what tmux answers here.
tab() {
  out=$("$SCRIPT" "$1" 2>&1)
  status=$?
  [ "$status" -eq 0 ] || fail "$2: exited $status"
  [ -z "$out" ] || fail "$2: printed [$out]"
  [ ! -f "$FAKE_TMUX_STATE/unexpected" ] || fail "$2: asked tmux something it does not answer:
$(state calls)"
}

[ -x "$SCRIPT" ] || fail "no executable script at $SCRIPT"

# The current pane and a closed pane are skipped; the most recent left wins.
given ' %5 %3 %9 %1 ' %5 %9 %1
tab %5 'a closed pane in the way'
assert_eq "$(state client)" %9
assert_eq "$(state history)" ' %5 %9 %1 '
assert_eq "$(state message)" ''

# The current pane need not be in the history.
given ' %9 %1 ' %5 %9 %1
tab %5 'the current pane missing from the history'
assert_eq "$(state client)" %9

# Nowhere to go: a message, no switch.
for h in UNSET ' ' ''; do
  given "$h" %5
  tab %5 "an empty history [$h]"
  assert_eq "$(state client)" ''
  assert_contains "$(state message)" 'no earlier pane'
  assert_eq "$(state history)" ' '
done

given ' %5 %3 %7 ' %5
tab %5 'every other pane closed'
assert_eq "$(state client)" ''
assert_contains "$(state message)" 'no earlier pane'
assert_eq "$(state history)" ' %5 '

# A switch tmux refuses: a message, nothing printed, still 0.
given ' %5 %9 ' %5 %9
: > "$FAKE_TMUX_STATE/fail-switch"
tab %5 'a refused switch'
assert_eq "$(state client)" ''
assert_contains "$(state message)" 'could not switch'

# A refused write-back still switches.
given ' %5 %3 %9 ' %5 %9
: > "$FAKE_TMUX_STATE/fail-set"
tab %5 'a refused write-back'
assert_eq "$(state client)" %9
assert_eq "$(state history)" ' %5 %3 %9 '

# The panes cannot be listed: a message, no switch.
given ' %5 %9 ' %5 %9
mv "$FAKE_TMUX_STATE/panes" "$FAKE_TMUX_STATE/gone"
out=$("$SCRIPT" %5 2>&1)
status=$?
assert_eq "$status" 0
assert_eq "$out" ''
assert_contains "$(state message)" 'could not list'
assert_eq "$(state client)" ''

# Whole ids: %1 closed leaves %12, and %12 closed leaves %1.
given ' %5 %1 %12 ' %5 %12
tab %5 '%1 closed, %12 open'
assert_eq "$(state client)" %12
assert_eq "$(state history)" ' %5 %12 '

given ' %5 %12 %1 ' %5 %1
tab %5 '%12 closed, %1 open'
assert_eq "$(state client)" %1
assert_eq "$(state history)" ' %5 %1 '

given ' %1 %12 ' %1 %12
tab %1 'current %1 with %12 behind it'
assert_eq "$(state client)" %12

# The write-back is padded at both ends, so the hook's " <id> " match keeps
# working, and an id in it twice is kept once.
given ' %3 %0' %3 %0
tab %3 'an unpadded history'
assert_eq "$(state history)" ' %3 %0 '
assert_eq "$(state client)" %0

given ' %3 %0 %3 %0 ' %3 %0
tab %3 'a history with duplicates'
assert_eq "$(state history)" ' %3 %0 '
