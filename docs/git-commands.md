# git commands

Branch and worktree housekeeping: what the commands decide, how they decide it, and
what stops them.

They live in `home/common/bin/` and `install.sh` links each into `~/bin`, which
`path.sh` puts on `PATH`. Git resolves a file called `git-foo` on `PATH` as the
subcommand `git foo`, so no aliases are involved. That is deliberate: an alias is a
one-line home, and anything with a decision in it belongs in a script that can be read
and tested.

Every one of them prints its plan and touches nothing until you say otherwise. Each
script's header carries the reasoning behind its own choices, including the ones that
went wrong the other way.

## The verdict

The question every cleanup asks is whether a branch's work is already in the trunk.
Three things can answer it, in order.

**Ancestry.** If the branch is an ancestor of `origin/HEAD`, its commits are in the
trunk and there is nothing more to ask.

**A merged pull request, but only as an exact match.** The branch tip has to be the
same commit the pull request merged. That answers the squash case, where none of the
branch's own commits survive in the trunk and there is nothing for a content search to
find. Commit to the branch after the merge and it stops counting, because that commit
exists nowhere else while the pull request still says merged.

**Content.** Walking the branch tip first, each commit's cumulative diff against the
fork point is stripped of its headers and hashed, and looked up in an index of the
trunk's own commit diffs. The first hit is where the branch joined; anything above it
is work the trunk does not have.

A deleted remote branch is never the verdict. It is a cross-check, and it earns a
mention only when it disagrees with the content: merged with the remote still there, or
the remote gone with nothing found.

That produces six answers:

| | |
|---|---|
| `empty` | nothing of its own, so it is the trunk under another name |
| `merged` | its work is in the trunk |
| `review` | merged up to a point, with commits sitting on top |
| `suspect` | the remote is gone and the content cannot be found |
| `inconclusive` | too far behind to have been evaluated |
| `unmerged` | work of its own, not in the trunk |

`inconclusive` needs both halves of a cap: more than a hundred commits behind the trunk
*and* untouched for thirty days. A recent branch on a busy repository is far behind and
still worth comparing; an old branch on a quiet one is a few commits either way.
`--old` turns the cap off and `--branch` exempts what you name.

A worktree with no branch on it has nothing to speak for it, so the commit it is parked
on is the subject instead. Its work being in the trunk, or a merged pull request
carrying it, means it is finished. A branch still holding it, or an open pull request,
means something is still going on. Neither is reported as unsure rather than guessed
at, and its age is never consulted.

## Bringing the trunk in

The strategy follows the branch's own history.

The trunk fast-forwards, and only ever fast-forwards. A branch that has already merged
the trunk into itself merges again, because a rebase would flatten that merge away and
discard whatever was resolved in it. Everything else is rebased.

A rebase is given the branch's fork point, not its merge base. For a branch cut from
another branch those differ, and the merge base is where the *other* branch left the
trunk, so a plain rebase replays that branch's commits too and publishes them under new
ids as though they were yours. Where two live branches genuinely share history past the
trunk, no update is offered at all, because nothing can tell which was cut from which.

What happens afterwards follows from what was done. A fast-forward publishes nothing so
it is not pushed. A merge rewrites nothing so its push is ordinary. A rebase rewrote
history, so it is force-pushed with a lease.

## What stops a command

**Uncommitted changes stop a removal, always.** There is no case where deleting a
worktree is worth risking work that exists nowhere else. Ignored files count: neither
`git status` nor `git worktree remove` reports them, so a worktree whose only extra
content is ignored reads as clean, and what would go with it is listed before it goes.

**Uncommitted changes do not stop an update.** An update only has to get past git, and
git refuses far less than a dirty tree suggests: a rebase refuses any tracked change at
all, while a fast-forward or a merge refuses only when the incoming commits touch a path
you have touched. Whether a stash is needed is worked out before anything is attempted,
and the operation says so when it is.

**A remote that has moved stops an update.** If the branch's own remote holds commits
the branch does not, a rebase would replay and force-push over them, and
`--force-with-lease` does not prevent it: the lease compares against the remote-tracking
ref, which the fetch at the start of the run has already moved onto the commit in
question.

**Order matters, which is why `git refresh` exists.** Bringing the trunk in first
rewrites committer dates, so every branch then looks freshly touched to the age a
cleanup reads, and it replays commits onto branches that were about to be deleted. As
two commands that order is something to remember. As one it cannot be expressed
wrongly.

## The commands

### git refresh

Cleanup and update in one pass over one snapshot. Every operation is on an interactive
list, whether or not it can run, because a row you cannot act on is usually what
explains the row above or below it. Space toggles, `r` runs, `q` quits.

A target's two halves are tied. An update starts wherever its own removal starts, so the
command never proposes maintaining a branch it is proposing to delete, and taking the
removal masks the update entirely.

`--plan` prints the same list and stops, which is also what happens with no terminal.
`--base`, `--branch`, `--depth`, `--old`, `--no-fetch` and `-v` behave as they do in
`git cleanup`.

### git cleanup

Reports every branch and what it would do to it. Nothing is deleted without `--apply`,
and each class beyond the plainly merged needs its own flag as well: `--empty` for
branches that never diverged, `--gone` for ones whose remote is gone and whose content
cannot be found, `--detached` for worktrees with no branch, `--rescue` to move the stray
commits off a `review` branch onto `rescue/<branch>` before deleting the original.

On an Azure DevOps remote it reads `cleanup.subscription` from git config to know which
identity to authenticate as. Without it the pull request check is skipped rather than
run as whichever account happens to be default. See `CLAUDE.md` for where to set it.

### git spread

Brings the trunk into every worktree of the repository. `--stash` sets uncommitted
changes aside first and puts them back afterwards. `--apply` acts.

### git catchup

The same for the branch you are standing in, then pushes it. It refuses unless the
branch and its remote are the same commit, because a rebase that fails at push time
leaves local history rewritten against a remote holding someone else's work.

### git main

Puts the default branch at origin's tip and puts you on it, in a single operation that
either happens or does not. Commits that would be orphaned are tagged `git-main/<name>-<timestamp>`
first, because git's own output is identical whether it fast-forwarded or discarded
them. Nothing prunes those tags.

### git wt-create

Creates the sibling worktree `<repo>--<leaf>` and prints its path. The branch is
resolved the way `git checkout` resolves one: an existing local branch is checked out, a
branch that exists on the remote is checked out and tracked, and only a name that exists
nowhere becomes a new branch. A base can be given only in that last case, and is refused
rather than ignored in the others.

Standard output is the path and nothing else, so the `wt` shell function can capture it
and `cd`, which a subprocess cannot do for its caller.
