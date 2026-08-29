#!/bin/sh
# Parse every shell script in this repo, then lint them with shellcheck. Quiet on
# success; a finding exits 1, and a missing linter exits 64.
#
# Each file is parsed by the interpreter its shebang names, before anything is
# linted, because shellcheck has its own parser and it is more permissive than
# the shell. A `case` inside `$( )` is fine to shellcheck and a syntax error to
# the bash 3.2 that is /bin/sh on macOS, so a green lint has never meant the
# script can run. The parse check goes first because `set -e` ends the run on
# shellcheck's own findings, and the failure that stops a script working must not
# be the one that gets skipped.
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
unparseable=
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case $(file "$f") in
    *'Bourne-Again shell script'*) set -- "$@" "$f"; bash -n "$f" || unparseable="$unparseable $f" ;;
    *'shell script'*)              set -- "$@" "$f"; /bin/sh -n "$f" || unparseable="$unparseable $f" ;;
  esac
done <<EOF
$(find . -type f -not -path './.git/*' -not -path '*/node_modules/*')
EOF

[ "$#" -gt 0 ] || { echo "found no shell scripts to lint" >&2; exit 64; }

[ -z "$unparseable" ] || { echo "will not parse:$unparseable" >&2; exit 1; }

shellcheck --format=gcc "$@"
