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

## Map

- `install.sh` — symlink installer (`home/` → `$HOME`)
- `setup.sh` → `setup/<os>/setup.sh` — per-OS bootstrap
- `load.sh` — shell-config router (`env` / `interactive` phases)
- `get-os.sh` — OS detection oracle
- `home/{common,<os>}/`, `os/`, `setup/<os>/`, `.gitconfig.d/`, `.vscode/`

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
