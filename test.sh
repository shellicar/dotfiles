#!/bin/sh
# Parse every shell script in this repo, then lint them with shellcheck. Quiet on
# success; a finding exits 1, and a missing linter exits 64. The shell fragments
# are parsed too, each by its own shell, though shellcheck cannot lint them.
#
# Each file is parsed by the interpreter its shebang names, before anything is
# linted, because shellcheck has its own parser and it is more permissive than
# the shell. A `case` inside `$( )` is fine to shellcheck and a syntax error to
# the bash 3.2 that is /bin/sh on macOS, so a green lint has never meant the script
# can run. The parse check goes first because `set -e` ends the run on a lint
# finding, and the failure that stops a script working must not be the one that
# gets skipped. A comment must not open with the linter's name, or the linter reads
# it as a directive and stops analysing the file there.
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
#
# The loader's fragments are matched by name rather than by `file`, the one exception
# to the rule above it. load.sh sources `<shell>/interactive.<shell>`, and a sourced
# fragment carries no shebang, so `file` reports plain text and the name is the only
# handle on which shell it belongs to. They are parsed and not linted, shellcheck
# having neither zsh nor a way to know.
set --
unparseable=
note_unparseable() {
  unparseable="$unparseable
$1"
}
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in
    *.zsh)  zsh -n "$f" || note_unparseable "$f"; continue ;;
    *.bash) bash -n "$f" || note_unparseable "$f"; continue ;;
  esac
  case $(file "$f") in
    *'Bourne-Again shell script'*) set -- "$@" "$f"; bash -n "$f" || note_unparseable "$f" ;;
    *'shell script'*)              set -- "$@" "$f"; /bin/sh -n "$f" || note_unparseable "$f" ;;
  esac
done <<EOF
$(find . -type f -not -path './.git/*' -not -path '*/node_modules/*')
EOF

[ "$#" -gt 0 ] || { echo "found no shell scripts to lint" >&2; exit 64; }

[ -z "$unparseable" ] || { printf 'will not parse:%s\n' "$unparseable" >&2; exit 1; }

# -x follows a sourced file, so a command and the library under home/common/lib
# are analysed together. Without it every variable the library defines for its
# front-ends reads as unused, and every function the front-end calls reads as
# undefined. The path is resolved by the source-path=SCRIPTDIR directive in each
# command, so it works from any working directory.
shellcheck -x --source-path=SCRIPTDIR --format=gcc "$@"
