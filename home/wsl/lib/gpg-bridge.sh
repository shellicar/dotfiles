#!/bin/sh
#
# gpg-bridge.sh: what gpg-bridge, gpg-bridge-install and setup/wsl/gpg-setup.sh
# share. Starting the Windows agent is defined here and nowhere else, the
# install's plan and --doctor read the same state queries, and the install
# itself lives here so its command is argument parsing and a call.
#
# Sourced, never run. Every function is WSL only.
#
# The systemd user service has no Windows directories on its PATH, so every
# Windows program is called by its full path.

GPG_BRIDGE_SERVICE=gpg-bridge.service
GPG_BRIDGE_MASKED_UNITS='gpg-agent.socket gpg-agent-extra.socket gpg-agent-ssh.socket gpg-agent-browser.socket'

GPG_BRIDGE_RELAY_VERSION=v1.12.1
GPG_BRIDGE_RELAY_URL="https://github.com/albertony/npiperelay/releases/download/${GPG_BRIDGE_RELAY_VERSION}/npiperelay_windows_amd64.exe"
GPG_BRIDGE_RELAY_SHA256=dbb448aea38835a65e2e10d83e2dd770a8e4dfa5f43b5669d7551a3125445ca4

# The Windows GnuPG install. Starting the agent depends on this file.
GPG_BRIDGE_WIN_GPGCONF='C:\Program Files\GnuPG\bin\gpgconf.exe'

# The Windows startup entry that starts the agent at logon.
GPG_BRIDGE_RUN_KEY='HKCU\Software\Microsoft\Windows\CurrentVersion\Run'
GPG_BRIDGE_RUN_VALUE=gpg-agent

# Starting the Windows agent. --headless runs gpgconf.exe without opening a
# console window. The Run entry is resolved by Windows, which finds conhost.exe
# on its own PATH; the bridge's call needs the full path.
GPG_BRIDGE_CONHOST='conhost.exe'
GPG_BRIDGE_RUN_DATA="$GPG_BRIDGE_CONHOST --headless \"$GPG_BRIDGE_WIN_GPGCONF\" --launch gpg-agent"

# A program in Windows' System32, as a WSL path.
gpg_bridge_system32() {
  wslpath -u "C:\\Windows\\System32\\$1"
}

# Starts the Windows gpg-agent, and does nothing when it is already running.
# stdin is closed so a caller holding a connection on it never lends it to a
# Windows process.
gpg_bridge_start_agent() {
  "$(gpg_bridge_system32 "$GPG_BRIDGE_CONHOST")" --headless "$GPG_BRIDGE_WIN_GPGCONF" --launch gpg-agent </dev/null
}

# A Windows environment variable holding a path. Returns 1 when interop is
# down, which wslvar reports on stdout with exit status 0, so the answer is
# accepted only when it looks like a drive path.
gpg_bridge_win_var() {
  value=$(wslvar "$1" 2>/dev/null || true)
  case "$value" in
    [A-Za-z]:\\*) printf '%s\n' "$value" ;;
    *) return 1 ;;
  esac
}

# The same, as a WSL path.
gpg_bridge_win_dir() {
  value=$(gpg_bridge_win_var "$1") || return 1
  wslpath -u "$value"
}

gpg_bridge_relay_path() {
  profile=$(gpg_bridge_win_dir USERPROFILE) || return 1
  echo "$profile/bin/npiperelay.exe"
}

# ok, missing or mismatch. A present but wrong or truncated relay is replaced,
# not trusted.
gpg_bridge_relay_state() {
  if [ ! -f "$1" ]; then
    echo missing
  elif [ "$(sha256sum "$1" | cut -d' ' -f1)" = "$GPG_BRIDGE_RELAY_SHA256" ]; then
    echo ok
  else
    echo mismatch
  fi
}

# The packaged gpg-agent units that are not masked yet, space separated.
# Masked, not disabled: Ubuntu enables them globally, which a user-level disable
# does not turn off.
gpg_bridge_unmasked_units() {
  unmasked=''
  for unit in $GPG_BRIDGE_MASKED_UNITS; do
    state=$(systemctl --user is-enabled "$unit" 2>/dev/null || true)
    [ "$state" = masked ] || unmasked="$unmasked $unit"
  done
  echo "${unmasked# }"
}

gpg_bridge_service_active() {
  [ "$(systemctl --user is-active "$GPG_BRIDGE_SERVICE" 2>/dev/null || true)" = active ]
}

gpg_bridge_service_enabled() {
  [ "$(systemctl --user is-enabled "$GPG_BRIDGE_SERVICE" 2>/dev/null || true)" = enabled ]
}

# is-system-running exits non-zero for "degraded" too, which only means a user
# unit failed, as gpg-bridge.service does once the key has been undocked a while.
gpg_bridge_systemd_running() {
  manager=$(systemctl --user is-system-running 2>/dev/null || true)
  case "$manager" in
    running|degraded) return 0 ;;
    *) return 1 ;;
  esac
}

# Prints the Run entry's stored data. Returns 1 when the entry is absent, and 2
# when the registry could not be read, with reg.exe's own error on stderr.
gpg_bridge_run_entry() {
  if ! out=$("$(gpg_bridge_system32 reg.exe)" query "$GPG_BRIDGE_RUN_KEY" /v "$GPG_BRIDGE_RUN_VALUE" 2>&1); then
    case "$out" in
      *'unable to find'*) return 1 ;;
      *) printf '%s\n' "$out" | tr -d '\r' | sed '/^$/d' >&2; return 2 ;;
    esac
  fi
  printf '%s\n' "$out" | tr -d '\r' \
    | sed -n "s/^ *$GPG_BRIDGE_RUN_VALUE  *REG_[A-Z_]*  *//p"
}

gpg_bridge_write_run_entry() {
  "$(gpg_bridge_system32 reg.exe)" add "$GPG_BRIDGE_RUN_KEY" /v "$GPG_BRIDGE_RUN_VALUE" \
    /t REG_SZ /d "$GPG_BRIDGE_RUN_DATA" /f >/dev/null
}

# Puts the relay in place and hands this distro's gpg-agent socket to it.
# Prints the plan, and carries it out when $1 is 1. Each step checks its own end
# state, so a re-run resumes a partial install.
gpg_bridge_install() {
  apply="$1"
  tool=gpg-bridge-install

  # Must work in ssh, cron, sudo and systemd sessions, which lack WSL's
  # environment variables.
  grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null || { echo "$tool: WSL only" >&2; return 2; }

  for cmd in wslvar wslpath socat curl sha256sum systemctl gpgconf gpg; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "$tool: missing $cmd" >&2; return 1; }
  done

  gpg_bridge_systemd_running || { echo "$tool: systemd --user is not running" >&2; return 1; }

  relay=$(gpg_bridge_relay_path) || { echo "$tool: could not read USERPROFILE from Windows" >&2; return 1; }
  relay_state=$(gpg_bridge_relay_state "$relay")
  need_mask=$(gpg_bridge_unmasked_units)
  need_service=0
  gpg_bridge_service_active || need_service=1

  # The plan lists only what is left to change.
  echo "plan: bridge gpg-agent to the Windows agent"
  echo "  relay        $relay"
  case "$relay_state" in
    ok)       echo "               already present, SHA-256 matches" ;;
    missing)  echo "               download $GPG_BRIDGE_RELAY_VERSION and verify SHA-256" ;;
    mismatch) echo "               SHA-256 does not match, download $GPG_BRIDGE_RELAY_VERSION and replace" ;;
  esac
  echo "  socket       $(gpgconf --list-dirs agent-socket)"
  if [ -n "$need_mask" ]; then
    echo "  mask         $need_mask"
  else
    echo "  mask         already masked"
  fi
  if [ "$need_service" -eq 1 ]; then
    echo "  service      enable and start $GPG_BRIDGE_SERVICE"
  else
    echo "  service      already active"
  fi

  if [ "$apply" -ne 1 ]; then
    echo "run: $tool --apply"
    return 0
  fi

  if [ "$relay_state" != ok ]; then
    tmp=$(mktemp -d)
    relay_new="$tmp/npiperelay.exe"
    trap 'rm -rf "$tmp"' EXIT INT TERM
    echo "downloading $GPG_BRIDGE_RELAY_VERSION"
    curl -fsSL -o "$relay_new" "$GPG_BRIDGE_RELAY_URL"
    got=$(sha256sum "$relay_new" | cut -d' ' -f1)
    if [ "$got" != "$GPG_BRIDGE_RELAY_SHA256" ]; then
      echo "$tool: checksum mismatch" >&2
      echo "  expected $GPG_BRIDGE_RELAY_SHA256" >&2
      echo "  got      $got" >&2
      return 1
    fi
    mkdir -p "$(dirname "$relay")"
    chmod +x "$relay_new"
    mv -f "$relay_new" "$relay"
    echo "  installed $relay"
  fi

  if [ -n "$need_mask" ]; then
    # Masking leaves a running unit running, and a running agent keeps the socket.
    # shellcheck disable=SC2086  # deliberate split, one word per unit
    systemctl --user stop $need_mask 2>/dev/null || true
    systemctl --user stop gpg-agent.service 2>/dev/null || true
    # shellcheck disable=SC2086
    systemctl --user mask $need_mask
    echo "  masked $need_mask"
  fi

  systemctl --user daemon-reload
  systemctl --user enable --now "$GPG_BRIDGE_SERVICE"
  echo "  $GPG_BRIDGE_SERVICE enabled"

  # The socket appears a moment after the service starts.
  socket=$(gpgconf --list-dirs agent-socket)
  waited=0
  while [ ! -S "$socket" ] && [ "$waited" -lt 50 ]; do
    sleep 0.1
    waited=$((waited + 1))
  done

  # An active unit proves nothing: socat stays up when the Windows side is broken.
  if gpg --card-status >/dev/null 2>&1; then
    echo "card reachable through the bridge"
  else
    echo "$tool: bridge up but the card did not answer" >&2
    echo "  check the key is in the dock, then: gpg --card-status" >&2
    return 1
  fi
}
