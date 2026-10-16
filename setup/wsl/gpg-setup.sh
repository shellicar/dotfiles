#!/bin/sh
#
# GPG setup, WSL: setup/linux/gpg-setup.sh plus what only WSL needs. The card is
# held by the Windows gpg-agent and reached through gpg-bridge, so there is no
# local agent, pinentry or scdaemon to configure; the Windows side is configured
# from here instead.

set -eu

DIR=$(cd "$(dirname "$0")" && pwd)

GPG_SETUP_SOURCED=1
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../linux/gpg-setup.sh
. "$DIR/../linux/gpg-setup.sh"
# shellcheck source=../../home/wsl/lib/gpg-bridge.sh
. "$DIR/../../home/wsl/lib/gpg-bridge.sh"

# gpg-agent has no infinite value: the man page defines both TTLs as plain
# seconds, and 0 means no caching at all rather than never expiring. 400 days is
# the stand-in, since the agent dies at logout long before it elapses.
CACHE_TTL_HARDWARE=34560000

# No --generate here: key generation is always on-card, identical regardless
# of OS (see docs/yubikey.md), and is not needed from WSL.

# Steps that could not be done. --configure carries on past them and fails at
# the end.
blocked=0

start_agent() {
  gpg_bridge_start_agent
}

# To gpg, a stopped bridge looks the same as an absent card.
require_agent() {
  if ! gpg_bridge_service_active; then
    echo "ERROR: $GPG_BRIDGE_SERVICE is not running" >&2
    echo "  the Windows agent holds the card; nothing here can reach it without the bridge" >&2
    echo "  run: gpg-bridge-install --apply" >&2
    exit 1
  fi
}

# Without no-autostart, gpg silently starts a keyless local agent instead of
# reaching the card through the bridge.
test_sign_check() {
  if ! has_conf_line "$GPG_CONF" no-autostart; then
    echo "ERROR: gpg.conf does not have no-autostart set" >&2
    echo "  run gpg-setup.sh --configure first" >&2
    exit 1
  fi
}

test_sign() {
  if ! linux_test_sign; then
    echo "  if the key is present but signing fails, the PIN prompt appears on Windows" >&2
    exit 1
  fi
}

windows_agent_conf_text() {
  printf 'default-cache-ttl %s\nmax-cache-ttl %s\n' "$CACHE_TTL_HARDWARE" "$CACHE_TTL_HARDWARE"
}

# A daily kill in cron reaches the Windows agent through the bridge too.
remove_cron() {
  if crontab -l 2>/dev/null | grep -q 'gpgconf --kill gpg-agent'; then
    crontab -l 2>/dev/null | grep -v 'gpgconf --kill gpg-agent' | crontab -
    echo "  Removed the daily gpg-agent kill from cron"
  else
    echo "  no leftover cron entry"
  fi
}

# Without it the Windows agent runs its out-of-the-box cache (10 minutes /
# 2 hours); the card should only need its PIN once.
configure_windows_agent_conf() {
  appdata=$(gpg_bridge_win_dir APPDATA) || {
    echo "  BLOCKED: could not read APPDATA from Windows, so the Windows gpg-agent.conf was not written" >&2
    blocked=1
    return 0
  }
  win_agent_conf="$appdata/gnupg/gpg-agent.conf"
  if [ -f "$win_agent_conf" ] && [ "$(cat "$win_agent_conf")" = "$(windows_agent_conf_text)" ]; then
    echo "  Windows gpg-agent cache: already ${CACHE_TTL_HARDWARE}s"
    return 0
  fi
  mkdir -p "$(dirname "$win_agent_conf")"
  windows_agent_conf_text > "$win_agent_conf"
  echo "  Windows gpg-agent cache: ${CACHE_TTL_HARDWARE}s (agent lifetime, in practice)"
  echo "  config: $win_agent_conf"

  # Makes a running agent re-read gpg-agent.conf without stopping it. An agent
  # that is not running reads it when it starts. Through the bridge, this
  # connection also starts the agent when it is down.
  # TODO(claude): undecided: whether --configure reloads the agent after changing
  # gpg-agent.conf, which uses the agent outside the key step. It reloads for now,
  # and only when the file changed.
  if gpg-connect-agent --no-autostart reloadagent /bye >/dev/null 2>&1; then
    echo "  Windows gpg-agent reloaded"
  else
    echo "  Windows gpg-agent not reached; it reads the new cache settings when it next starts"
  fi
}

# The Windows startup entry that starts the agent at logon. Read first and
# written only when it differs.
configure_run_entry() {
  if [ ! -f "$(wslpath -u "$GPG_BRIDGE_WIN_GPGCONF")" ]; then
    echo "  WARNING: $GPG_BRIDGE_WIN_GPGCONF not found; the startup entry cannot start the agent until GnuPG is installed there" >&2
  fi

  status=0
  current=$(gpg_bridge_run_entry) || status=$?
  if [ "$status" -eq 2 ]; then
    echo "  BLOCKED: could not read the Windows registry, so the startup entry was not written" >&2
    blocked=1
    return 0
  fi
  if [ "$status" -eq 0 ] && [ "$current" = "$GPG_BRIDGE_RUN_DATA" ]; then
    echo "  Windows startup entry: already set"
    return 0
  fi

  if ! gpg_bridge_write_run_entry; then
    echo "  BLOCKED: reg.exe could not write $GPG_BRIDGE_RUN_KEY\\$GPG_BRIDGE_RUN_VALUE" >&2
    blocked=1
    return 0
  fi
  status=0
  current=$(gpg_bridge_run_entry) || status=$?
  if [ "$status" -ne 0 ] || [ "$current" != "$GPG_BRIDGE_RUN_DATA" ]; then
    echo "  ERROR: the startup entry reads back differently from what was written" >&2
    echo "    expected: $GPG_BRIDGE_RUN_DATA" >&2
    echo "    stored:   $current" >&2
    blocked=1
    return 0
  fi
  echo "  Windows startup entry: written ($GPG_BRIDGE_RUN_KEY\\$GPG_BRIDGE_RUN_VALUE)"
}

configure() {
  for arg in "$@"; do
    case "$arg" in
      # Accepted so the macOS command line works here; nothing to configure.
      --hardware) ;;
      --touch)
        echo "ERROR: --touch is not supported on WSL: keep-chv-on-timeout needs a patched scdaemon," >&2
        echo "  and the Windows scdaemon is not known to be patched" >&2
        exit 64 ;;
      *) echo "ERROR: unknown option: $arg" >&2; exit 64 ;;
    esac
  done

  echo "GPG Configuration (WSL, card via the Windows agent)"
  echo "==================================================="
  echo ""

  linux_configure_files
  # Without no-autostart, gpg starts a keyless local agent when the bridge is down.
  ensure_conf_line "$GPG_CONF" no-autostart
  remove_cron
  configure_windows_agent_conf
  configure_run_entry
  linux_configure_key

  echo ""
  if [ "$blocked" -ne 0 ]; then
    echo "Not finished: the steps marked BLOCKED or ERROR above were not done." >&2
    exit 1
  fi
  echo "Done. Signing uses the Windows pinentry; the PIN prompt appears there."
}

# A kill from WSL reaches the Windows agent through the bridge. The bridge reads
# the socket file on every connection, so it needs no restart.
reset_agent() {
  echo "Restarting the Windows gpg-agent..."
  gpgconf --kill gpg-agent

  # Waited out so the start does not find the old agent still exiting.
  local_appdata=$(gpg_bridge_win_dir LOCALAPPDATA) || {
    echo "ERROR: could not read LOCALAPPDATA from Windows" >&2
    exit 1
  }
  win_socket="$local_appdata/gnupg/S.gpg-agent"
  waited=0
  while [ -e "$win_socket" ] && [ "$waited" -lt 50 ]; do
    sleep 0.1
    waited=$((waited + 1))
  done
  if [ -e "$win_socket" ]; then
    echo "ERROR: the Windows gpg-agent did not exit: $win_socket is still there" >&2
    exit 1
  fi

  start_agent
  echo "Done. Next sign will prompt for the PIN again."
}

# systemd --user, read without changing it.
doctor_systemd() {
  if ! out=$(systemctl --user is-system-running 2>&1); then
    case "$out" in
      degraded) ;;
      *'Failed to connect'*)
        check_unknown "gpg-bridge service and the masked gpg-agent units" "systemctl --user: $out"
        return 0 ;;
      *)
        check_bad "systemd --user is not running ($out)"
        return 0 ;;
    esac
  fi

  unmasked=$(gpg_bridge_unmasked_units)
  if [ -z "$unmasked" ]; then
    check_ok "packaged gpg-agent units masked"
  else
    check_bad "not masked: $unmasked" "run: gpg-bridge-install --apply"
  fi
  if gpg_bridge_service_enabled; then
    check_ok "$GPG_BRIDGE_SERVICE enabled"
  else
    check_bad "$GPG_BRIDGE_SERVICE not enabled" "run: gpg-bridge-install --apply"
  fi
  if gpg_bridge_service_active; then
    check_ok "$GPG_BRIDGE_SERVICE active"
  else
    check_bad "$GPG_BRIDGE_SERVICE not active" "see: systemctl --user status $GPG_BRIDGE_SERVICE"
  fi
}

doctor_checks() {
  linux_doctor_checks
  check_conf_line "$GPG_CONF" no-autostart "run: gpg-setup.sh --configure"
  if crontab -l 2>/dev/null | grep -q 'gpgconf --kill gpg-agent'; then
    check_bad "cron still kills gpg-agent daily" "run: gpg-setup.sh --configure"
  else
    check_ok "no daily gpg-agent kill in cron"
  fi

  echo ""
  echo "Bridge"
  for cmd in socat wslvar wslpath systemctl sha256sum; do
    check_command "$cmd"
  done
  doctor_systemd

  echo ""
  echo "Windows"
  win_gpgconf=$(wslpath -u "$GPG_BRIDGE_WIN_GPGCONF")
  if [ -f "$win_gpgconf" ]; then
    check_ok "$GPG_BRIDGE_WIN_GPGCONF exists"
  else
    check_bad "$GPG_BRIDGE_WIN_GPGCONF not found" "install GnuPG for Windows (Gpg4win) to its default location"
  fi
  conhost=$(gpg_bridge_system32 "$GPG_BRIDGE_CONHOST")
  if [ -f "$conhost" ]; then
    check_ok "$GPG_BRIDGE_CONHOST exists"
  else
    check_bad "$conhost not found"
  fi

  if ! relay=$(gpg_bridge_relay_path); then
    check_unknown "the relay, the startup entry and the Windows gpg-agent.conf" \
      "Windows interop is not available here: wslvar could not read USERPROFILE"
    return 0
  fi
  case $(gpg_bridge_relay_state "$relay") in
    ok)       check_ok "relay $relay, SHA-256 matches" ;;
    missing)  check_bad "relay $relay not found" "run: gpg-bridge-install --apply" ;;
    mismatch) check_bad "relay $relay SHA-256 does not match" "run: gpg-bridge-install --apply" ;;
  esac

  status=0
  err=$(gpg_bridge_run_entry 2>&1 >/dev/null) || status=$?
  case "$status" in
    0)
      current=$(gpg_bridge_run_entry)
      if [ "$current" = "$GPG_BRIDGE_RUN_DATA" ]; then
        check_ok "startup entry $GPG_BRIDGE_RUN_KEY\\$GPG_BRIDGE_RUN_VALUE"
      else
        check_bad "startup entry differs: $current" "run: gpg-setup.sh --configure"
      fi ;;
    1) check_bad "no startup entry $GPG_BRIDGE_RUN_KEY\\$GPG_BRIDGE_RUN_VALUE" "run: gpg-setup.sh --configure" ;;
    *) check_unknown "the startup entry" "reg.exe: $err" ;;
  esac

  appdata=$(gpg_bridge_win_dir APPDATA) || appdata=''
  win_agent_conf="$appdata/gnupg/gpg-agent.conf"
  if [ -z "$appdata" ]; then
    check_unknown "the Windows gpg-agent.conf" "could not read APPDATA from Windows"
  elif [ -f "$win_agent_conf" ] && [ "$(cat "$win_agent_conf")" = "$(windows_agent_conf_text)" ]; then
    check_ok "Windows gpg-agent.conf caches for ${CACHE_TTL_HARDWARE}s"
  else
    check_bad "$win_agent_conf does not hold the cache settings" "run: gpg-setup.sh --configure"
  fi
}

schedule() {
  echo "Not applicable under WSL."
  echo ""
  echo "  The macOS version schedules a daily 'gpgconf --kill gpg-agent' to bound"
  echo "  how long an on-disk key's decrypted passphrase stays cached. WSL is"
  echo "  hardware-only, and --configure already sets a ~400-day cache TTL on the"
  echo "  Windows agent, so a daily forced re-auth has nothing to protect here."
  exit 1
}

usage() {
  echo "Usage: $(basename "$0") <command>"
  echo ""
  echo "Commands:"
  echo "  --test-sign    Test signing with the key on the card, through the bridge"
  echo "  --test-sign --hardware"
  echo "                 The same thing. The card is the only key reachable here"
  echo "  --configure    Configure this distro and Windows to sign with the card"
  echo "  --configure --hardware"
  echo "                 The same thing. There is no on-disk key mode under WSL"
  echo "  --doctor       Check what is installed and configured, changing nothing"
  echo "  --doctor --hardware"
  echo "                 The same thing"
  echo "  --reset        Restart the Windows gpg-agent"
  echo "                 (next sign prompts for the PIN)"
  echo "  --schedule     Not applicable under WSL; explains why"
  exit 1
}

case "${1:-}" in
  --test-sign)  shift; test_sign "$@" ;;
  --configure)  shift; configure "$@" ;;
  --doctor)     shift; doctor WSL "$@" ;;
  --reset)      reset_agent ;;
  --schedule)   schedule ;;
  *)            usage ;;
esac
