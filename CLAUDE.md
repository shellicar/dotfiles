# CLAUDE.md

Operating context for an agent working in this repo. The human-facing overview is
in `README.md`; this file is the rules of the road for *changing* things here.

(`copilot.instructions.md` is a separate Copilot behavioural protocol — not a
description of this repo.)

## What this is

shellicar's dotfiles, cloned to `~/dotfiles`. Configuration is a **common base +
per-OS overlay**; the OS comes from `get-os.sh` (`windows-bash` | `wsl` | `macos`
| `linux`), the single source of OS truth.

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
- **`.config/` and `.local/` are outside `install.sh`'s reach.** It walks `home/`
  only, so those two are linked into `$HOME` by hand — `~/.config/git/hooks` is a
  whole-directory symlink made manually. Adding a file under them changes nothing
  until a link exists, and a rename there silently leaves a dangling link behind.

## Map

- `install.sh` — symlink installer (`home/` → `$HOME`)
- `setup.sh` → `setup/<os>/setup.sh` — per-OS bootstrap
- `load.sh` — shell-config router (`env` / `interactive` phases)
- `get-os.sh` — OS detection oracle
- `home/common/bin/` — executables linked per-file into `~/bin`, which `path.sh`
  prepends to `PATH` (see Commands)
- `home/{common,<os>}/`, `os/`, `setup/<os>/`, `.gitconfig.d/`, `.vscode/`
- `.config/git/hooks/`, `.local/bin/` — linked by hand, *not* by `install.sh`
- `docs/yubikey.md`: hardware-backed signing and auth decisions, and their reasoning

## Commands (`home/common/bin/`)

`install.sh` links each file into `~/bin`; `path.sh` prepends that to `PATH`. Git
resolves a file named `git-foo` there as the subcommand `git foo`, no alias needed
— which is why these are scripts rather than `[alias]` entries in
`.gitconfig.d/common`. A one-line alias is the wrong home for anything with real
logic: extract it here instead.

- `git-cleanup` — delete local branches, and their worktrees, whose work is
  already in main. The verdict is the merge check alone; a `gone` upstream is only
  a cross-check. Reads `[cleanup]` config (see Git).
- `git-spread` — bring `origin/main` into every worktree of the repo: `main`
  fast-forwards, the rest rebase.
- `git-catchup` — rebase the current branch onto the default branch and
  force-push it. Preflights that local and its remote are the same commit first.
- `git-wt-create` — create the sibling worktree `<repo>--<leaf>` and print its
  path. Resolves `<branch>` the way `git checkout` does: an existing local or
  remote branch is checked out and tracked, and only an unused name becomes a new
  branch off `origin/HEAD`. The `wt` function in `common.sh` wraps it to `cd`,
  which a subprocess cannot do for its caller.
- `gitversion` — GitVersion wrapper; finds its config by walking up the tree.
- `tmux-snapshot`, `tmux-snapshot-watch` — capture and rehydrate a tmux server's
  layout; the watcher is started by tmux itself via `run-shell -b`.

Each script's header comment carries its own reasoning. Read that before changing
one; it holds the why that the code cannot.

## Git

- **Identity/signing**: conditional by remote URL in `.gitconfig.d/`
  (`includeIf "hasconfig:remote.*.url:…"`).
- **Global ignore**: `core.excludesfile` → `~/dotfiles/.gitignore_global` — the
  always-never-commit patterns: `.DS_Store`, `*.log`, `CLAUDE.local.md`,
  `**/.claude/.*` (every hidden file inside any `.claude/` — session/runtime
  state), and `**/.claude/settings.local.json` (Claude Code's local-scope
  settings — personal, never shared). Other non-dot `.claude/` files such as
  `sdk-config.json`, `agents/`, and `skills/` are committable.
- **Two `.claude` adoption levels** (chosen per repo, by context):
  1. *Checked in* (e.g. shellicar, eagers): `.claude/` is committed. Only
     `.claude/.*`, `.claude/settings.local.json`, and `CLAUDE.local.md` are kept
     out, by the global ignore above.
  2. *Not checked in / not referenced* (hopeventures): the whole `.claude/` is
     kept out per-clone via `.git/info/exclude` (`.claude/`), leaving no trace in
     the repo or its history — not even a `.gitignore` entry naming it.
- Level 2 isn't centralisable: `core.excludesfile` is single-valued (last-wins),
  so a conditional `includeIf` would *replace* rather than stack, and committing
  the ignore would itself be a trace. Hence per-clone `info/exclude`.
- **Hooks**: `core.hooksPath` → `~/.config/git/hooks`, a hand-made symlink to
  `.config/git/hooks` here. `pre-push` gates the *remote* ref name rather than the
  local branch (a local checkout can be called anything; what lands on the remote
  is what matters): only `docs/ fix/ hotfix/ security/ feature/ epic/ review/`.
  `pre-commit` delegates to the repo's own `.git/hooks/pre-commit` when one
  exists, so a per-repo hook still runs.
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

`./test.sh` shellchecks every shell script here. Run it after changing one. It is
quiet on success, exits 1 on a finding, and exits 64 when it cannot lint at all —
never 0 for "did not actually run", which is the bug it used to have. Targets are
found with `file`, not by extension, because most scripts here are commands on
`PATH` with no extension. Nothing in `setup/` installs shellcheck, so it falls
back to the `koalaman/shellcheck` container when the binary is absent.

The scripts are POSIX `sh`, and the environments span BSD and GNU coreutils, so a
GNU-only flag to `sed` or `date` passes on Linux and fails on the Mac.
