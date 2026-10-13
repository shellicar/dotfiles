# git commands

Branch and worktree housekeeping: what the commands decide, how they decide it, and
what stops them.

They live in `home/common/bin/` and `install.sh` links each into `~/bin`, which
`path.sh` puts on `PATH`. Git resolves a file called `git-foo` on `PATH` as the
subcommand `git foo`, so no aliases are involved. That is deliberate: an alias is a
one-line home, and anything with a decision in it belongs in a script that can be read
and tested.

Every one of them prints its plan and touches nothing until you say otherwise. Each
script's header says what someone changing it needs to know, including approaches that
were tried and did not work.

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

**Content.** A commit's work is in the trunk when merging it into the trunk changes
nothing: `git merge-tree --write-tree origin/HEAD <commit>` prints the same tree as
`origin/HEAD^{tree}`. Walking down from the branch tip, children before parents, the
first commit that passes is the branch's **landed commit**. Everything from it down
counts as in the trunk, and everything above it is the branch's own work. The test
compares the commit with the whole trunk rather than with any one commit of it, so a
branch whose work landed as several separate squash merges still passes.

The walk stops at the first pass and never tests below it. A commit lower down can
fail after the trunk has changed the same lines again, even though its work landed,
so a failure there says nothing.

The merge is git's, so it uses the repository's merge drivers. A driver that keeps one
side, such as `CHANGELOG merge=ours`, can make a branch that only changed that file read
as merged.

It tests at most 50 commits, or `--depth N`. A branch with more commits than that and
no pass among them is reported as not checked, rather than as unmerged.

The commands need git 2.38 or newer, for `merge-tree --write-tree`; everything else
they use is older: `show --remerge-diff` (2.36), `rev-list --no-commit-header` (2.33)
and the `GIT_CONFIG_COUNT` variables that carry the pins (2.31). `git-common.sh`
checks `git --version` when it is loaded, so every command refuses on an older git,
and on output it cannot read, before doing anything else. A git error from
`merge-tree` stops the command with git's message rather than reading as "not in the
trunk". `merge-tree` writes the merged tree into the object store, where nothing refers
to it and `git gc` removes it. Each answer is cached under
`cleanup-cache/in-main/<trunk tip>/` in the repository's common git directory, which
every worktree shares, and each run removes the answers for every other tip.

A deleted remote branch is never the verdict. It is a cross-check, and it earns a
mention only when it disagrees with the content: merged with the remote still there, or
the remote gone with nothing found.

That produces seven answers:

| | |
|---|---|
| `empty` | nothing of its own, so it is the trunk under another name |
| `merged` | its work is in the trunk |
| `review` | in the trunk up to its landed commit, with commits on top |
| `suspect` | the remote is gone and the content cannot be found |
| `inconclusive` | too far behind to have been evaluated |
| `unchecked` | more commits than the walk tests, and none of those tested had landed |
| `unmerged` | work of its own, not in the trunk |

**Rescue or rebase.** A `review` branch gets one of two things. When one of its own
pull requests merged, meaning a merged pull request's source branch has this branch's
name and its last commit is among the branch's commits the trunk does not have, the
commits above the landed commit were added after that merge, and it is offered the
rescue: those commits move to `rescue/<branch>` and the original goes. The name is
required as well as the commit: a branch cut from another branch whose pull request
merged holds that pull request's last commit too, and is not the branch the pull
request was for. Otherwise its landed commit reached the trunk some other way, for
instance as commits on a local trunk that were squash-merged upstream from other
branches, and the branch is kept; once it is checked out in a worktree, `git refresh`
rebases it from the landed commit and keeps the worktree. That includes a branch with
no pull request information at all, a branch squash-merged by hand, and a branch
renamed after its pull request merged. Both hosts answer the question the same way:
GitHub's `headRefName` and `headRefOid`, and Azure DevOps's `sourceRefName` and
`lastMergeSourceCommit`, are each pull request's source branch and last commit.

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

The trunk fast-forwards, and only ever fast-forwards. Everything else is rebased by
`git refresh`, including a branch that has merged the trunk into itself.

A rebase replays only the commits that are not merges, so a merge that carries edits of
its own, a resolved conflict or a change made while the merge was open, loses them.
`git show --remerge-diff <merge>` shows exactly those edits. When a merge above where
the rebase starts has any, the rebase is still offered, unticked, and its row names the
merge and the files. A rebase with nothing to drop is ticked as usual. This replaced
merging the trunk in again for a branch that had merged it before, in `git refresh`:
the rebase is offered with a warning rather than refused, and `git refresh` no longer
offers that merge to your own branches.

`git spread` and `git catchup` still merge again into a branch that has merged the
trunk, since neither can leave a rebase unticked behind a warning. For any other
rebase that would drop a merge's edits, `git spread` skips the branch and says so, and
`git catchup` names the merge and the files in its plan.

A rebase starts from the branch's landed commit when it has one, so the work already in
the trunk is not replayed onto it a second time. Otherwise it is given the branch's fork
point, not its merge base. For a branch cut from another branch those differ, and the
merge base is where the *other* branch left the trunk, so a plain rebase replays that
branch's commits too and publishes them under new ids as though they were yours. Where
two live branches genuinely share history past the trunk, no update is offered at all,
because nothing can tell which was cut from which. Commits under the landed commit do
not count as shared history: their work is in the trunk, so several branches cut from
the same unpushed commits, which then landed upstream, are each rebased.

In `git refresh`, a branch is yours only when every commit it has that the trunk does
not is authored under the email the repository resolves to, exactly. Anything else is
someone else's branch, checked out to review or built on, and theirs to rebase. It is
offered a merge instead, unticked, with the row saying whose commits they are. The merge
is pushed, and with no upstream nothing is offered, because a merge left local on a
branch its author pushes to only waits to conflict. An upstream that is configured and
then pruned away reaches the merge anyway, and a merge that ends up local says so and
names the commit to go back to, because which way to resolve it is yours. There is deliberately no list of
your other addresses: a commit under an old identity reads as not yours, which is how it
gets noticed. A bot you run is not you. `git spread` has nowhere to offer a merge
unticked, so it skips the branch and says whose it is. `git catchup` does not ask.

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

**A lock stops a removal, and nothing else.** git refuses to remove, move or prune a
worktree locked with `git worktree lock`, and Claude Code locks the worktrees it
creates. Every lock blocks, whether or not whatever took it is still running. The
removal is shown as unavailable with `locked:` and git's reason beside it, in the same
place uncommitted changes are named. A lock does not stop an update: `git refresh`
still offers one and `git spread` still makes it.

**When git refuses a removal, what it said is shown** under the line reporting it,
every line of it.

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

## Your git config

The commands run under whatever config the repository, your global file and the
system file set, and some settings would make them do what their plan does not show.
`rebase.updateRefs` is the one that started this: under it, a rebase also moves every
other local branch pointing into the replayed range. So the settings that change what
a command does are pinned, and everything else is yours.

**How.** `git-common.sh` appends the pins to `GIT_CONFIG_COUNT`, `GIT_CONFIG_KEY_<n>`
and `GIT_CONFIG_VALUE_<n>` when it is sourced, and every command sources it. Git reads
those after the system, global and repository files, so a pin wins over all three, and
the environment reaches every git a command starts, including the ones git starts
itself. Entries already in the environment are kept. `git -c key=value <command>` is
read after the environment, so it overrides a pin for that one run, which is the way to
change a pinned setting when you need to. A new git call in a
command is pinned without doing anything; a new setting that changes behaviour goes in
the list in `git-common.sh`.

Programs a command starts inherit the pins too: pnpm in `git wt-create`, `az`, `gh`.
They run and exit, so the pins last for that one call. VS Code is the exception: `git
review` removes the entries it added, and only those, before it launches VS Code. If
`code` starts a new VS Code instead of handing off to a running one, that process keeps
its environment for as long as it runs, and every terminal opened in it would have the
pins on git you run by hand.

The variables need git 2.31 or newer; older git would ignore them, and the pins would
silently not apply. That cannot happen: the commands refuse any git older than 2.38
(see "Content" under "The verdict").

**Pinned.** Each value is the one git uses when nothing is set, with two exceptions,
noted in their rows: `rerere.enabled` and `submodule.recurse`, where pinning differs
from leaving the setting unset.

| Setting | Value | What a different value would do |
|---|---|---|
| `rebase.updateRefs` | `false` | move other local branches along with a rebase |
| `rebase.autoStash` | `false` | set a dirty tree aside and carry on, where the commands rely on git refusing |
| `merge.autoStash` | `false` | the same for a merge or fast-forward |
| `rebase.rebaseMerges` | `false` | recreate merges instead of replaying a flat range |
| `rebase.backend` | `merge` | the apply backend treats empty commits and hooks differently |
| `merge.ff` | `true` | `only` refuses the merge of the trunk into a branch |
| `merge.directoryRenames` | `conflict` | `true` moves a file added in a directory the other side renamed, where git would stop |
| `merge.renormalize` | `false` | `true` lets an edit through a line-ending conversion on the other side, where git would stop |
| `merge.renames` | `true` | `false`, or `diff.renames=false` when it is unset, turns a rename against an edit into a conflict, and adds a file under a renamed directory at the old path without one |
| `rerere.enabled` | `false` | resolve a conflict from an old recording instead of stopping on it. When unset, git turns rerere on if `.git/rr-cache` exists; pinning `false` keeps it off even then, which is the difference wanted |
| `fetch.pruneTags`, `remote.origin.pruneTags` | `false` | delete local tags origin lacks on every fetch, `git main`'s tags among them |
| `push.default` | `simple` | `matching` pushes every branch with a remote counterpart |
| `push.followTags` | `false` | push tags along with the branch |
| `push.recurseSubmodules` | `no` | `on-demand` pushes the submodules' commits as well, which no plan shows |
| `branch.autoSetupMerge` | `true` | `always` makes `rescue/<branch>` track the local branch about to be deleted; `false` leaves the main `git main` recreates with no upstream |
| `submodule.recurse` | `false` | carry switch, merge and rebase into submodules. Unlike leaving it unset, `false` also switches off fetch's default of fetching the submodule commits new superproject commits point to; the next row puts that back. Push and fetch each read it as the same switch as their own setting, whichever is read last winning |
| `fetch.recurseSubmodules` | `on-demand` | git's default fetch behaviour, restored after the `submodule.recurse` pin. It comes after that pin in the list for the reason above |
| `status.showUntrackedFiles` | `normal` | `no` hides untracked files from the dirty checks |

One setting cannot go in the list, because its key names a branch:
`branch.<name>.mergeOptions`. Options such as `-Xtheirs` in it would settle a conflict
silently; `--autostash` in it carries a fast-forward over a dirty tree despite the
`merge.autoStash` pin, and `--squash` makes a fast-forward stage the trunk's changes and
leave the branch where it was. So every merge the commands run goes through one helper
in `git-common.sh`, `merge_without_branch_options`, which clears it for the branch it
merges: the merge and the fast-forward in `carry_out_update` (`git refresh`, `git
spread`) and the same two in `git catchup`. That helper is the one exception to keeping
the pins in one list. It clears the setting with `--config-env`, not `-c`: `-c` splits
at the first `=`, so for a branch named `a=b` it would set a different key and leave
the real one in force. A rebase does not read the setting (checked on git 2.55).

`rebase.autoSquash` is not pinned: it only affects an interactive rebase, and none of
the commands runs one (checked on git 2.55). None of them runs `git pull`, so
`pull.rebase` and `pull.ff` do not reach them.

**Yours**, read from your config as they always were:

- *Who you are and how you sign*: `user.*`, the `includeIf` files that set them,
  `commit.gpgsign`, `tag.gpgSign`, `gpg.*`. A command's commits are yours.
- *Hooks*: `core.hooksPath`, so the push gate and the commit-message hook run.
- *Credentials and transport*: `credential.*`, `http.*`, remote URLs, `remote.pushDefault`
  and `branch.<name>.pushRemote`.
- *Settings the commands read on purpose*: `cleanup.subscription`, `cleanup.azconfig`,
  `claude.sessionTrailer`.
- *Checks that can only refuse*: `merge.verifySignatures`, `push.useForceIfIncludes`.
  Under them an operation fails and the refusal shows in the command's output; nothing
  extra happens.
- *What content is*: line endings, filters, ignore rules.
- *Display*: colour, diff and log formatting, `advice.*`. What git prints straight to
  you follows them. What a command parses is read with plumbing and explicit formats
  (`rev-list --format`, `for-each-ref --format`, `diff-tree`, `status --porcelain`), which
  these settings do not change.

Two calls read settings beyond those. The check for whether a commit's work is in the
trunk, `git merge-tree --write-tree`, merges as git would, so it reads `merge.*` and
the rename settings: `merge.renames`, `merge.directoryRenames` and `merge.renormalize`
are pinned above, so your values of those three do not change its answer, and the
repository's merge drivers apply. `git show
--remerge-diff`, which lists the files a merge edited by hand, reads the diff settings;
it is called with `--no-renames`, `--no-color`, `--no-ext-diff` and `--name-only`,
which leave only the list of paths to depend on them.

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
commits off a `review` branch whose own pull request merged onto `rescue/<branch>`
before deleting the original. A `review` branch without one is kept and listed, for
`git refresh` to rebase. `--depth N` sets how many commits the walk for a landed commit
tests, 50 by default.

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

### git review

`git review <branch> <base>` opens the checkout it is run from in VS Code, or the
repository itself when it is bare, and shows `<base>`
against `<branch>` in GitLens's Search & Compare view. Both refs are checked first, and
a name git does not know stops it before VS Code opens. The base is always given,
because git does not record which branch another was cut from. The base is
used exactly as given, so a review against origin's copy says `origin/main`: a local
`main` can be behind or deleted. The link hands GitLens the merge base of the base and
the branch as a commit id, not the base's name: Search & Compare's file list diffs the
two refs' tips directly (read from GitLens 19.3.0's source), so a base that has moved on would show what it gained as if the
branch had deleted it. From the merge base, the list is what the branch adds, the way a
pull request shows it.

Opening VS Code is per platform: `vscode-open-review` in `home/<os>/bin`. On WSL it
opens the folder through a `vscode-remote://wsl+…` address and hands the GitLens link
to Windows with `Start-Process`. The macOS and Linux ones refuse until each has been
tried on that platform.
