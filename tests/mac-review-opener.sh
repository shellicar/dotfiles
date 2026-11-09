#!/bin/sh
# Sourced by the cases for home/macos/bin/vscode-open-review, after harness.sh.
#
# The opener runs as a program, from a bin/ and a lib/ side by side the way
# install.sh links them into $HOME, because it sources the library from ../lib.
# VS Code is never started: code, pgrep and git are stand-ins on PATH.
#   code   writes one line to $CODE_LOG per call, each argument in brackets, so
#          a case sees what VS Code was handed and in what order; and appends
#          the GIT_CONFIG_ variables it was started with to $CODE_ENV.
#   pgrep  finds VS Code running once a case has called vscode_is_running.
#   git    answers the version check the library makes when it is sourced, and
#          fails anything else.
#
# TODO(claude): undecided: whether the cases assert the exact code calls, which
# a different way of reaching VS Code breaks even when it lands the same, or
# something less tied to them. The exact calls for now: they are the only thing
# the opener produces.

mkdir -p "$WORK/bin" "$WORK/lib" "$WORK/fakes"
ln -s "$REPO/home/macos/bin/vscode-open-review" "$WORK/bin/vscode-open-review"
ln -s "$REPO/home/common/lib/git-common.sh" "$WORK/lib/git-common.sh"

CODE_LOG=$WORK/code.log
CODE_ENV=$WORK/code.env
VSCODE_RUNNING=$WORK/vscode-running
: > "$CODE_LOG"
: > "$CODE_ENV"
export CODE_LOG CODE_ENV VSCODE_RUNNING

cat > "$WORK/fakes/code" <<'FAKE'
#!/bin/sh
printf '[%s]' "$@" >> "$CODE_LOG"
printf '\n' >> "$CODE_LOG"
env | grep '^GIT_CONFIG_' | sort >> "$CODE_ENV"
exit 0
FAKE
cat > "$WORK/fakes/pgrep" <<'FAKE'
#!/bin/sh
[ -e "$VSCODE_RUNNING" ]
FAKE
cat > "$WORK/fakes/git" <<'FAKE'
#!/bin/sh
[ "$*" = --version ] && { echo 'git version 2.55.0'; exit 0; }
printf 'test: the opener asked git for more than its version: git %s\n' "$*" >&2
exit 97
FAKE
chmod +x "$WORK/fakes/code" "$WORK/fakes/pgrep" "$WORK/fakes/git"

vscode_is_running() { : > "$VSCODE_RUNNING"; }

# open_review ARGS...: runs the opener with the stand-ins first on PATH.
open_review() {
  PATH=$WORK/fakes:$PATH "$WORK/bin/vscode-open-review" "$@"
}
