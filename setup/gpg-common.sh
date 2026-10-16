#!/bin/sh
#
# gpg-common.sh: what every OS's gpg-setup.sh shares. Sourced, never run.
#
# start_agent is the one definition of starting the agent on macOS and Linux.
# setup/wsl/gpg-setup.sh redefines it to start the Windows agent instead, so
# nothing on WSL reaches the gpgconf here, which would start a local agent with
# no keys.

start_agent() {
  gpgconf --launch gpg-agent
}

# True when the file has the option on a line of its own.
has_conf_line() {
  [ -f "$1" ] && grep -qx "$2" "$1"
}

add_conf_line() {
  mkdir -p "$(dirname "$1")"
  chmod 700 "$(dirname "$1")"
  # Without a final newline the option would join the file's last line.
  if [ -s "$1" ] && [ -n "$(tail -c 1 "$1")" ]; then
    echo >> "$1"
  fi
  echo "$2" >> "$1"
}

# Rewritten through a temporary file, since sed -i takes different arguments on
# BSD and GNU.
remove_conf_line() {
  tmp_conf="$1.tmp.$$"
  grep -vx "$2" "$1" > "$tmp_conf" || true
  cat "$tmp_conf" > "$1"
  rm -f "$tmp_conf"
}

# Makes sure the option is set, and says which way it went.
ensure_conf_line() {
  if has_conf_line "$1" "$2"; then
    echo "  $(basename "$1"): $2 already set"
  else
    add_conf_line "$1" "$2"
    echo "  $(basename "$1"): $2 added"
  fi
}

# --- --doctor ---
# Each check reports one of three things: it is right, it is wrong, or it could
# not be looked at. The last is never reported as missing.

doctor_problems=0
doctor_unknown=0

check_ok() {
  printf '  ok         %s\n' "$1"
}

# $1 what is wrong, $2 optionally what fixes it.
check_bad() {
  printf '  PROBLEM    %s\n' "$1"
  [ -z "${2:-}" ] || printf '             %s\n' "$2"
  doctor_problems=$((doctor_problems + 1))
}

# $1 what was not checked, $2 why.
check_unknown() {
  printf '  UNCHECKED  %s\n' "$1"
  [ -z "${2:-}" ] || printf '             %s\n' "$2"
  doctor_unknown=$((doctor_unknown + 1))
}

check_command() {
  if command -v "$1" >/dev/null 2>&1; then
    check_ok "$1 installed"
  else
    check_bad "$1 not installed" "${2:-}"
  fi
}

# $1 file, $2 option, $3 what sets it.
check_conf_line() {
  if has_conf_line "$1" "$2"; then
    check_ok "$1 has $2"
  else
    check_bad "$1 does not have $2" "$3"
  fi
}

# The key is in the keyring and marked ultimately trusted. Reads the keyring
# only; the agent and the card are not used.
check_public_key() {
  if gpg --list-keys "$1" >/dev/null 2>&1; then
    check_ok "public key $1 in the keyring"
  else
    check_bad "public key $1 is not in the keyring" "run: gpg-setup.sh --configure, with the key in"
    return 0
  fi
  if gpg --export-ownertrust 2>/dev/null | grep -q "^$1:6:"; then
    check_ok "public key marked ultimately trusted"
  else
    check_bad "public key is not marked ultimately trusted" "run: gpg-setup.sh --configure"
  fi
}

# Exits 0 only when every check passed.
doctor_verdict() {
  echo ""
  if [ "$doctor_problems" -eq 0 ] && [ "$doctor_unknown" -eq 0 ]; then
    echo "Everything looks right."
    exit 0
  fi
  [ "$doctor_problems" -eq 0 ] || echo "$doctor_problems problem(s) found."
  [ "$doctor_unknown" -eq 0 ] || echo "$doctor_unknown check(s) could not be made."
  exit 1
}
