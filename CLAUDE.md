# CLAUDE.md

Operating context for an agent working in this repo. The human-facing overview is
in `README.md`; this file is the rules of the road for *changing* things here.

(`copilot.instructions.md` is a separate Copilot behavioural protocol — not a
description of this repo.)

## What this is

shellicar's dotfiles, cloned to `~/dotfiles`. Configuration is a **common base +
per-OS overlay**; the OS comes from `get-os.sh` (`wsl` | `macos` | `linux`), the
single source of OS truth.

Each OS has one supported shell: zsh on macOS, bash on Linux and WSL2. Windows is
not supported. Nothing here has to make zsh work on Linux or bash work on macOS.

## Invariants — do not break these

- **The path is the condition.** Per-OS behaviour is selected by filename
  (`os/<os>.rc.sh`, `home/<os>/…`), never by runtime `if [ "$os" = macos ]`. To
  change OS-specific behaviour, edit or add the OS-specific file.
- **Overlays are optional; don't create empty ones.** e.g. `os/wsl.env.sh` exists
  but there is no `os/wsl.rc.sh`. A file exists only when it has content.
- **`install.sh` is one-way and non-clobbering.** It symlinks `home/common` +
  `home/<os>` into `$HOME`, moving any existing real file to `<name>.pre-dotfiles`
  first. Keep it idempotent and re-runnable.
- **`home/macos/.gitconfig` and `home/linux/.gitconfig` are the live `~/.gitconfig`**
  (symlinked). Edits take effect immediately on the running machine.
- **`bin/` tools are dry-run by default.** Anything that deletes, rewrites history
  or force-pushes prints its plan on no args; `--apply` is the only flag that acts.
  Every other flag narrows *what is in the plan*, never causes it to happen.
- **Anything destined for `$HOME` lives under `home/`.** `install.sh` walks that
  tree and nothing else. Directories are linked per-file unless named in
  `is_whole_dir()`, which symlinks the directory itself: `.hammerspoon`, and
  `.config/git/hooks` so a hook added there is live without re-running anything.
- **`.local/` is not linked, and does not need to be.** `.tmux.conf` calls its
  script by repo path, so nothing under it has to exist in `$HOME`.

## Map

- `install.sh` — symlink installer (`home/` → `$HOME`)
- `setup.sh` → `setup/<os>/setup.sh` — per-OS bootstrap
- `load.sh` — shell-config router (`env` / `interactive` phases)
- `get-os.sh` — OS detection oracle
- `home/common/bin/` — executables linked per-file into `~/bin`, which `path.sh`
  prepends to `PATH` (see Commands)
- `home/common/lib/` — sourced by the commands in `bin/`, linked into `~/lib`.
  `git-common.sh` holds every decision the git commands make: which branches are
  merged, what a detached worktree is, how to bring the trunk in, so a command
  in `bin/` is argument parsing and a call to `main`. `tmux-snapshot.sh` is the
  same for `tmux-snapshot`: saving, the restore plan, the status view.
  `yubikeys.sh` holds the three serials.
- `tests/` — behavioural tests for the above. No repository is built: `git` is a
  shell function backed by a fake commit graph, so a case states a situation
  directly instead of committing its way to one.
- `home/{common,<os>}/`, `os/`, `setup/<os>/`, `.gitconfig.d/`, `.vscode/`
- `.local/bin/` — not linked into `$HOME`; called by repo path
- `docs/yubikey.md`: hardware-backed signing and auth decisions, and their reasoning
- `docs/git-commands.md`: what the git commands decide, how, and what stops them

## Commands (`home/common/bin/`)

`install.sh` links each file into `~/bin`; `path.sh` prepends that to `PATH`. Git
resolves a file named `git-foo` there as the subcommand `git foo`, no alias needed
— which is why these are scripts rather than `[alias]` entries in
`.gitconfig.d/common`. A one-line alias is the wrong home for anything with real
logic: extract it here instead.

- `git-refresh` — remove what has landed and bring the trunk into what survives,
  picked from an interactive list
- `git-cleanup` — delete local branches, and their worktrees, whose work is
  already in main
- `git-spread` — bring the trunk into every worktree of the repo
- `git-catchup` — bring the trunk into the current branch and push it
- `git-main` — put the default branch at origin's tip and switch to it
- `git-wt-create` — create the sibling worktree `<repo>--<leaf>` and print its
  path
- `git-review`: show a branch against its base in VS Code, in GitLens's Search
  & Compare view
- `azure-files-sync`: keep local folders and Azure Files shares in step, both
  ways, as set in `${XDG_CONFIG_HOME:-~/.config}/azure-files-sync/`
- `gitversion` — GitVersion wrapper
- `tmux-snapshot`, `tmux-snapshot-watch` — capture and rehydrate a tmux server's
  layout

`docs/git-commands.md` is the documentation: the model they share, what each one
decides, and what stops it. A script's comments are for someone who did not write
it, and the test for each one is whether that reader needs it, and for what: a
constraint, a trap, or an approach that was tried and failed, so it is not tried
again. Justification argues that a choice was right, which protects whoever made
it and gives the reader nothing to act on. What helps them is the decision
itself, recorded the way an ADR records one: what was chosen, in what context, and
what it rules out. That goes in the commit, the PR or the doc, and a comment keeps
to what someone changing the code needs in front of them. Read the header before
changing one, and put what you learn there or in the doc rather than here.
This list says only what a command is for, so that changing how one behaves leaves
this file alone.

## Git

- **Identity/signing**: conditional by remote URL in `.gitconfig.d/`
  (`includeIf "hasconfig:remote.*.url:…"`).
- **Global ignore**: `core.excludesfile` → `~/dotfiles/.gitignore_global` — the
  always-never-commit patterns: `.DS_Store`, `*.log`, `CLAUDE.local.md`,
  `**/.claude/.cc-writes/` (Claude Code's staging folder for saving its own
  config files), `**/.claude/settings.local.json` (Claude Code's local-scope
  settings — personal, never shared), `**/.claude/worktrees/` (Claude Code
  worktrees, each a separate checkout), and `**/.claude/tasks/` and
  `**/.claude/docs/` (working files, never committed; anything that needs to be
  checked in goes in the repo's `docs/`). Other `.claude/` files such as
  `sdk-config.json`, `agents/`, and `skills/` are committable.
- **Two `.claude` adoption levels** (chosen per repo, by context):
  1. *Checked in* (e.g. shellicar, eagers): `.claude/` is committed. Only
     `.claude/.cc-writes/`, `.claude/settings.local.json`, `.claude/worktrees/`,
     `.claude/tasks/`, `.claude/docs/`, and `CLAUDE.local.md` are kept out, by
     the global ignore above.
  2. *Not checked in / not referenced* (hopeventures): the whole `.claude/` is
     kept out per-clone via `.git/info/exclude` (`.claude/`), leaving no trace in
     the repo or its history — not even a `.gitignore` entry naming it.
- Level 2 isn't centralisable: `core.excludesfile` is single-valued (last-wins),
  so a conditional `includeIf` would *replace* rather than stack, and committing
  the ignore would itself be a trace. Hence per-clone `info/exclude`.
- **Hooks**: `core.hooksPath` → `~/.config/git/hooks`, which `install.sh` symlinks
  whole to `home/common/.config/git/hooks`. `pre-push` gates the *remote* ref name
  rather than the local branch (a local checkout can be called anything; what lands
  on the remote is what matters): only `docs/ fix/ hotfix/ security/ feature/ epic/ review/`.
  `pre-commit` delegates to the repo's own `.git/hooks/pre-commit` when one
  exists, so a per-repo hook still runs. `commit-msg` delegates the same way,
  after adding a `Claude-Session: <id>` trailer to commits made from a Claude Code
  session, but only where `claude.sessionTrailer = true` is set (per org, in
  `.gitconfig.d/<org>`).
- **`[cleanup]` is per org, set beside `user.email`**: `git-cleanup` reads
  `cleanup.subscription`, a subscription in the ADO org's tenant, which is what
  selects the identity to mint an ADO token as. Without it the PR check is skipped
  rather than run as whichever account happens to be default. Add
  `cleanup.azconfig` (a private `AZURE_CONFIG_DIR`) only where two orgs need
  different identities on the *same* subscription — one profile holds one login
  per subscription, so the second login evicts the first. Never set either
  globally.

## VS Code (gotcha)

- `.vscode/settings.json` is **merged** into the live settings, not symlinked —
  VS Code writes machine-local state into that file, so a symlink would pump it
  back into the repo. It is the **single source** for every OS: the per-OS keys
  (`terminal.integrated.defaultProfile.osx`/`.linux`/`.windows`) are distinct
  setting IDs that each host self-selects, so only the *destination path* is
  platform-specific — not the settings.
- `.vscode/sync.mjs` does the merge. **Dry-run is the default (no args) and
  doubles as a drift view; `--apply` WRITES** (timestamped backup first).
  It deep-merges the repo source into the live file, **preserving machine-local
  keys** (repo values win only on the keys the source defines). OS decides the
  target path only (macOS, Git Bash, WSL; native Linux is not synced).

## Testing

`./test.sh` parses every shell script here, then shellchecks it, then runs the
behavioural suite in `tests/`. Run it after changing one.

It exits 1 on this tree today and always has, on a standing set of deliberate
shellcheck findings: mostly `local` (not POSIX, used throughout on purpose) and
unquoted expansions that are meant to split. Every one of those classes has a
counterpart on main, so none of them is new. The exit status therefore cannot
tell you a test failed. The suite prints its own verdict instead, `tests: N
passed` or `tests: N of M FAILED`, and that line is what to read. The bar for a
change is no new finding *class*, not a clean exit, which is why the count is
not written down here: it moves with every line added and the classes do not.

It exits 64 when it cannot lint at all —
never 0 for "did not actually run". Targets are
found with `file`, not by extension, because most scripts here are commands on
`PATH` with no extension. Nothing in `setup/` installs shellcheck, so it falls
back to the `koalaman/shellcheck` container when the binary is absent.

The scripts are POSIX `sh`, and the environments span BSD and GNU coreutils, so a
GNU-only flag to `sed` or `date` passes on Linux and fails on the Mac.

`tests/integration/run.sh` is the other half, and is not part of `./test.sh`: it
needs docker. It builds real repositories in a container and runs the commands
against them for real. Two kinds of thing belong here rather than in `tests/`,
and both for the same reason, that the answer has to come from git and not from
us: carrying a plan out, because deciding and doing are different code and the
pure suite can only reach the first; and any claim about what git itself does,
which is checked by predicting it and then attempting the operation. The
container is what makes running it safe: it deletes branches and worktrees for
real, and none of them are yours. It skips with a message when docker is absent.

`tests/sync/run.sh` tests `azure-files-sync`'s library, and is not part of
`./test.sh` either. It needs rclone and git, and runs the real rclone (bisync
included) against two local folders it makes, one standing in for the Azure
Files share, so it never contacts Azure. It covers how a resync treats files
that differ on the two sides, and `keep-local` / `keep-remote`. Run it after
changing `azure-files-sync` or `home/common/lib/azure-files-sync.sh`. A missing
rclone exits 64; it never skips.

`tests/tmux/run.sh` tests `tmux-snapshot` against a real tmux, and is not part
of `./test.sh` either. It needs docker: each case runs in a fresh container
built from `tests/tmux/Dockerfile` (alpine with tmux, no Node), with the repo
mounted read-only, so the servers it starts and kills are never yours. It
prints the tmux version it ran against. It covers save, kill and restore round
trips, sessions named `""` and names holding `:` or `.`, the `@snapshot-error`
mark and the status bar segment, and the old JSON files being left alone. The
unit cases in `tests/cases/` fake tmux with `tests/fake-tmux.sh`; anything about
how tmux itself treats an argument belongs here instead. Run it after changing
`tmux-snapshot` or `home/common/lib/tmux-snapshot.sh`. A missing docker, or an
image that will not build, exits 64; it never skips.

A case in `tests/cases/` builds no repository. It sources the library, replaces
`git` with a shell function backed by a fake commit graph, and asserts on what
came back. Two rules earn their keep: assert on state rather than on which
commands were issued, so a rewrite that reaches the same end still passes; and
model reachability properly, because a case that stubs `rev-list` can describe a
repository git cannot produce, and one written that way stayed green while the
behaviour it claimed to cover was broken.
