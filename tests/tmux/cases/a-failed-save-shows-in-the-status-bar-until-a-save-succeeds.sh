#!/bin/sh
# A save that cannot write sets @snapshot-error, which `show -sv` prints and
# the status-right in .tmux.conf shows; the next save that works unsets it.
set -u
# The path exists only inside the container, where run.sh mounts it.
# shellcheck source=../lib.sh
. /case/lib.sh

new_session main edit /work/a
tm split-window -h -t main:0 -c /work/b
settle

# status-right exactly as .tmux.conf sets it.
grep '^set -g status-right ' /repo/home/common/.tmux.conf > /work/status.conf
[ -s /work/status.conf ] || fail "no status-right line in .tmux.conf"
tm source-file /work/status.conf || fail "the status-right line does not load"
shown() { tm display-message -p -t main:0 "$(tm show -gv status-right)"; }
case $(shown) in *'snapshot failed'*) fail "the status bar shows a failure before any save" ;; esac
ok "nothing shown before a save"

# A data directory under the read-only mount: the save cannot create its
# directory, whoever runs it.
XDG_DATA_HOME=/repo/no-such-dir run -L "$L" save && fail "a save that could not write succeeded"
error=$(tm show -sv @snapshot-error) || fail "@snapshot-error is not set"
case $error in *'cannot create /repo/no-such-dir/tmux/snapshot/t'*) ;; *) fail "unexpected error text: $error" ;; esac
ok "show -sv @snapshot-error prints: $error"
tm show -gv @snapshot-error >/dev/null 2>&1 && fail "@snapshot-error was set as a global session option"
ok "it is a server option, not a global session option"
case $(shown) in *' snapshot failed '*) ;; *) fail "the status bar does not show the failure: $(shown)" ;; esac
ok "the status bar shows it: $(shown)"

run -L "$L" save || fail "the save failed"
tm show -sv @snapshot-error >/dev/null 2>&1 && fail "a successful save left @snapshot-error set"
ok "a successful save unset it"
case $(shown) in *'snapshot failed'*) fail "the status bar still shows the failure" ;; esac
ok "the status bar no longer shows it: $(shown)"

echo 'PASS a-failed-save-shows-in-the-status-bar-until-a-save-succeeds'
