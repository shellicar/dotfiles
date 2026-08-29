#!/bin/sh
# Lint every shell script in this repo with shellcheck. Quiet on success; a
# finding exits 1, and a missing linter exits 64.
#
# A SILENT PASS IS THE ONE OUTCOME THIS MUST NEVER PRODUCE. The original wrote
# the lint as `cmd "$f" && echo ok`, and set -e never fires for the left side of
# an && list, so both a missing binary and a genuine finding exited 0. Nothing
# here had ever actually been linted on a machine without it installed.
#
# The linter is declared in setup/macos/Brewfile and setup/linux/packages, so a
# bootstrapped machine has it, and its absence is a real error rather than a
# reason to reach for a container.
#
# gcc output format, not the default tty: one line per finding instead of six.
# The caller here is usually an agent, and the compact form is what it can scan
# without drowning. Run the linter on a single file by hand when you want the
# source echo and the "Did you mean" suggestion.
#
# Discovery is by `file`, not by extension: most scripts here have no extension
# because they are commands on PATH (home/common/bin/git-*). `file` reports both
# "POSIX shell script" and "Bourne-Again shell script", and neither for the node
# scripts or the vendored binary, so the substring is the whole test.

set -eu

cd "$(dirname "$0")"

command -v shellcheck >/dev/null 2>&1 || { echo "shellcheck is not installed: brew install shellcheck" >&2; exit 64; }

# Built as positional parameters so the paths stay quoted, and via a here-doc
# rather than a pipe so the loop is not a subshell and the list survives it.
set --
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case $(file "$f") in
    *'shell script'*) set -- "$@" "$f" ;;
  esac
done <<EOF
$(find . -type f -not -path './.git/*' -not -path '*/node_modules/*')
EOF

[ "$#" -gt 0 ] || { echo "found no shell scripts to lint" >&2; exit 64; }

# -x follows a sourced file, so a command and the library under home/common/lib
# are analysed together. Without it every variable the library defines for its
# front-ends reads as unused, and every function the front-end calls reads as
# undefined. The path is resolved by the 'shellcheck source-path=SCRIPTDIR'
# directive in each command, so it works from any working directory.
shellcheck -x --format=gcc "$@"
