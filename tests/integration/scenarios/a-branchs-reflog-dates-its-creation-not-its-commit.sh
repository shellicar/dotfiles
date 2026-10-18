#!/bin/sh
# git refresh dates an empty Claude Code subagent branch by when the branch was
# created, read from the oldest entry of its reflog:
#
#   git reflog --no-show-signature --date=unix --format=%gd refs/heads/<branch>
#
# its last line, and the digits between '@{' and '}'. That reading is only right
# if git prints what it is predicted to print here:
#
#   the last line is the oldest entry, <name>@{<seconds it was created>}
#   those seconds are the branch's creation, not its tip's commit date (%ct)
#   the same holds for a branch made by 'git worktree add -b', for a name with a
#     slash, and with log.showSignature=true on a signed tip
#   a ref that does not exist prints nothing and exits 128
#
# Each branch is created at a time chosen here, through GIT_COMMITTER_DATE, which
# git stamps on the reflog entry, and every tip commit is dated far from it, so
# a reading that took the commit date would not land on the creation time.
set -eu

# The path exists only inside the container, where run.sh mounts it.
# shellcheck source=../lib.sh
. /scenario/lib.sh

new_repo

now=$(date +%s)
day=86400
commit_at=$((now - 100 * day))

# The command git refresh runs, and its last line.
created_line() {
  git reflog --no-show-signature --date=unix --format=%gd "$1" | tail -1
}

# expect_created <ref> <seconds>: the last line ends in @{<seconds>}, and the
# tip's commit date is not that.
expect_created() {
  line=$(created_line "$1")
  case "$line" in
    *"@{$2}") ;;
    *) fail "$1: expected the last line to end in @{$2}, got [$line]" ;;
  esac
  ct=$(git log -1 --no-show-signature --format=%ct "$1")
  [ "$ct" != "$2" ] || fail "$1: its commit date is its creation time too, so this proves nothing"
  printf '  ok   %-40s %s (commit date %s)\n' "$1" "$line" "$ct"
}

# The tip every branch starts from, dated 100 days ago.
printf 'old\n' > old.txt
git add old.txt
GIT_AUTHOR_DATE="@$commit_at +0000" GIT_COMMITTER_DATE="@$commit_at +0000" \
  git commit -qm 'dated 100 days ago'

echo '--- git branch ---'
t=$((now - 8 * day))
GIT_COMMITTER_DATE="@$t +0000" git branch worktree-agent-plain main
expect_created refs/heads/worktree-agent-plain "$t"

echo '--- git worktree add -b ---'
t=$((now - 9 * day))
GIT_COMMITTER_DATE="@$t +0000" git worktree add -q -b worktree-agent-wt "$ROOT/wt-agent" main
expect_created refs/heads/worktree-agent-wt "$t"

echo '--- a name with a slash ---'
t=$((now - 10 * day))
GIT_COMMITTER_DATE="@$t +0000" git branch worktree-agent-a/b main
expect_created refs/heads/worktree-agent-a/b "$t"

echo '--- a later entry does not move the creation ---'
t=$((now - 11 * day))
later=$((now - 2 * day))
GIT_COMMITTER_DATE="@$t +0000" git branch worktree-agent-moved main
git switch -q worktree-agent-moved
printf 'later\n' > later.txt
git add later.txt
GIT_AUTHOR_DATE="@$later +0000" GIT_COMMITTER_DATE="@$later +0000" git commit -qm later
git switch -q main
entries=$(git reflog --no-show-signature --date=unix --format=%gd refs/heads/worktree-agent-moved | wc -l)
[ "$entries" -ge 2 ] || fail "worktree-agent-moved has $entries reflog entries, so this proves nothing"
expect_created refs/heads/worktree-agent-moved "$t"

echo '--- log.showSignature=true on a signed tip ---'
# An SSH key signs, because gpg is not in the image. allowedSignersFile makes the
# verification succeed, so what it prints is a signature line and not an error.
ssh-keygen -q -t ed25519 -N '' -C test@test -f "$ROOT/key" ||
  fail 'ssh-keygen could not make a signing key'
printf 'test@test %s\n' "$(cat "$ROOT/key.pub")" > "$ROOT/allowed"
git config gpg.format ssh
git config user.signingkey "$ROOT/key.pub"
git config gpg.ssh.allowedSignersFile "$ROOT/allowed"
signed_at=$((now - 50 * day))
printf 'signed\n' > signed.txt
git add signed.txt
GIT_AUTHOR_DATE="@$signed_at +0000" GIT_COMMITTER_DATE="@$signed_at +0000" git commit -qS -m signed
t=$((now - 12 * day))
GIT_COMMITTER_DATE="@$t +0000" git branch worktree-agent-signed main
git config log.showSignature true

# Without --no-show-signature the setting does add lines. If it did not, the
# flag would be guarding against nothing and the check below would prove nothing.
plain=$(git reflog --date=unix --format=%gd refs/heads/worktree-agent-signed)
printf '%s\n' "$plain" | sed 's/^/  without the flag: /'
[ "$(printf '%s\n' "$plain" | grep -cv '@{')" -gt 0 ] ||
  fail 'log.showSignature added no lines without --no-show-signature, so this proves nothing'
printf '  ok   without --no-show-signature, log.showSignature adds lines\n'

with=$(git reflog --no-show-signature --date=unix --format=%gd refs/heads/worktree-agent-signed)
[ "$(printf '%s\n' "$with" | grep -cv '@{')" -eq 0 ] ||
  fail "with --no-show-signature there are still lines that are not entries: [$with]"
expect_created refs/heads/worktree-agent-signed "$t"
git config --unset log.showSignature

echo '--- a ref that does not exist ---'
status=0
out=$(git reflog --no-show-signature --date=unix --format=%gd refs/heads/worktree-agent-missing 2>/dev/null) || status=$?
[ -z "$out" ] || fail "a missing ref printed [$out]"
[ "$status" = 128 ] || fail "a missing ref exited $status, expected 128"
printf '  ok   a missing ref prints nothing and exits 128\n'

echo 'PASS a-branchs-reflog-dates-its-creation-not-its-commit'
