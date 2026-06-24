# dotfiles

shellicar's dotfiles. Cloned to `~/dotfiles`.

(For agents working in this repo, see `CLAUDE.md`.)

## Model

Config is layered: a shared **common** base plus a **per-OS overlay**. The OS is
detected by `get-os.sh` — one of `windows-bash`, `wsl`, `macos`, `linux`. The
path/filename *is* the condition; there is no runtime `if macos` branching, and
overlay files exist only when there's something to put in them.

## Setup

- `./install.sh` — symlinks `home/common/` and `home/<os>/` into `$HOME`.
  Idempotent and re-runnable. An existing real file is moved to
  `<name>.pre-dotfiles` before linking, so nothing is clobbered.
- `./setup.sh` — per-OS bootstrap via `setup/<os>/setup.sh` (Homebrew `Brewfile`
  on macOS, packages on linux). Safe to run on a bare machine.

## Shell config

Sourced through `load.sh` in two phases:

- `env` — `env.sh` → `os/<os>.env.sh` → `path.sh`
- `interactive <shell>` — `common.sh` → `os/<os>.rc.sh` → `<shell>/interactive.<shell>`

## Layout

- `home/common/`, `home/<os>/` — files symlinked into `$HOME`
- `os/` — per-OS `env`/`rc` fragments
- `setup/<os>/` — bootstrap (`Brewfile`, `packages`)
- `.gitconfig.d/` — per-context git config (see Git)
- `.vscode/` — VS Code settings sync

## Git

- **Identity & signing** are conditional on the remote URL via `.gitconfig.d/`
  (`shellicar`, `eagers`, `hopeventures`), using
  `includeIf "hasconfig:remote.*.url:…"`.
- **Global ignore** is managed: `core.excludesfile` → `~/dotfiles/.gitignore_global`
  — the always-never-commit bits: `.DS_Store`, `*.log`, `CLAUDE.local.md`,
  `**/.claude/.*` (hidden session files inside any `.claude/`), and
  `**/.claude/settings.local.json` (Claude Code's personal local settings).
- **Two `.claude` adoption levels:**
  - *Checked in* (shellicar, eagers): `.claude/` is committed; only `.claude/.*`,
    `.claude/settings.local.json`, and `CLAUDE.local.md` are kept out. Other
    non-dot files like `.claude/sdk-config.json` are committed.
  - *Not checked in* (hopeventures): the whole `.claude/` is kept out per-clone
    via `.git/info/exclude`, leaving no trace in the repo — not even a `.gitignore`
    entry naming it. (Not centralisable: `core.excludesfile` is single-valued, and
    a committed ignore would itself be a trace.)

## VS Code

`.vscode/settings.json` is **merged** into the live settings, not symlinked —
VS Code writes machine-local state (paths, connections) into that file. Run
`.vscode/merge-settings.sh`: dry-run by default, `-d` / `--destructive` **writes**.
