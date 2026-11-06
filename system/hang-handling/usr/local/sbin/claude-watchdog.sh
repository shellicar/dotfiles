#!/bin/bash
# Claude D-state watchdog
# Finds claude processes stuck in uninterruptible sleep (D state) and kills
# one only once it has stayed stuck for GRACE seconds across checks. A short
# D state (slow disk or network I/O) clears by itself; the WSL2 hang doesn't.
# python processes stuck in D state are logged the same way but never killed.
# Any other process is logged, never killed, once it has stayed stuck for
# GRACE seconds, since a short D state is normal for one doing I/O.
# The kernel stack of a hang isn't read here (that needs root); the kernel
# logs it itself with kernel.hung_task_timeout_secs set.
# The timer runs this every few seconds; the state file remembers when each
# pid was first seen stuck, so a single run never waits.

GRACE=60
STATE_DIR="$HOME/.local/state/claude-watchdog"
STATE="$STATE_DIR/stuck"
LOG="$STATE_DIR/claude-watchdog.log"
mkdir -p "$STATE_DIR"

now=$(date +%s)
stamp() { date '+%Y-%m-%d %H:%M:%S'; }

# Reading a process's cmdline or memory takes its memory map lock, and blocks
# for as long as a process stuck in the kernel holds it (seen: a shellcheck in
# mmap, for hours). Those reads can be interrupted only by SIGKILL, so they're
# bounded with one; otherwise this run, and with it every later run of the
# timer, would hang behind the process it's describing.
bounded() { timeout -s KILL 2 "$@"; }

# What the process is, and what it's waiting on in the kernel.
describe() {
  local pid=$1 wchan cwd cmd
  wchan=$(cat "/proc/$pid/wchan" 2>/dev/null)
  cwd=$(readlink "/proc/$pid/cwd" 2>/dev/null)
  cmd=$(bounded tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null) || cmd="(unreadable) $(cat "/proc/$pid/comm" 2>/dev/null)"
  echo "wchan=${wchan:-?} cwd=${cwd:-?} cmd=${cmd:-?}"
}

# The path a thread's syscall was given, read from the process's memory at
# the pointer in /proc/<tid>/syscall ("nr arg0 arg1 ..." in hex). Only for
# syscalls that take a path; reading the memory needs the same access as
# the syscall line.
# TODO(claude): undecided: which syscalls are decoded. x86_64 numbers; path
# in arg0: open stat lstat access readlink; in arg1: openat readlinkat
# newfstatat faccessat statx faccessat2. Others print no path line.
syscall_path() {
  local t=$1 nr addr path
  local -a a
  read -r -a a <<< "$2"
  nr=${a[0]}
  case "$nr" in
    2|4|6|21|89) addr=${a[1]} ;;
    257|262|267|269|332|439) addr=${a[2]} ;;
    *) return 0 ;;
  esac
  [[ "$addr" == 0x* ]] || return 0
  # Read up to PATH_MAX bytes; a read that runs into an unmapped page stops
  # short. Keep everything before the first NUL.
  path=$(bounded dd if="$t/mem" bs=4096 count=1 skip=$(( addr )) iflag=skip_bytes 2>/dev/null \
    | head -z -n1 | tr -d '\0')
  if [[ -n "$path" ]]; then
    echo "      path: $path"
  else
    echo "      path: not readable at $addr"
  fi
}

# What it's stuck on, as far as a user can see: every thread in D state with
# its kernel wait point, and the files it has open on the Windows drives
# (9p mounts, where the WSL2 hangs happen). The syscall and its arguments
# (/proc/<pid>/syscall) and the kernel stack need root, or ptrace_scope 0, so
# they're tried and noted when refused.
detail() {
  local pid=$1 t st wc f target mounts
  echo "  detail pid=$pid"
  for t in /proc/"$pid"/task/*; do
    st=$(sed 's/.*) //' "$t/stat" 2>/dev/null | cut -d' ' -f1)
    [[ "$st" == D ]] || continue
    wc=$(cat "$t/wchan" 2>/dev/null)
    echo "    thread ${t##*/} D wchan=${wc:-?} name=$(cat "$t/comm" 2>/dev/null)"
    if f=$(cat "$t/syscall" 2>/dev/null); then
      echo "      syscall: $f"
      syscall_path "$t" "$f"
    else
      echo "      syscall: not readable (needs root or ptrace_scope 0)"
    fi
  done
  mounts=$(awk '$3 == "9p" {print $2}' /proc/mounts | sort -u)
  for f in /proc/"$pid"/fd/*; do
    target=$(readlink "$f" 2>/dev/null) || continue
    while read -r m; do
      [[ -n "$m" && "$target" == "$m"/* ]] && echo "    open fd ${f##*/} $target"
    done <<< "$mounts"
  done
  return 0
}

# A killed claude leaves its terminal as it had it: mouse reporting on (so
# mouse movement prints escape codes), possibly the alternate screen, a hidden
# cursor, and the tty in raw mode. Put the terminal back, unless a new claude
# is already running on it.
reset_tty() {
  local tty=$1 p
  [[ "$tty" == /dev/pts/* && -w "$tty" ]] || return
  for p in /proc/[0-9]*; do
    [[ "$(cat "$p/comm" 2>/dev/null)" == claude ]] || continue
    [[ "$(readlink "$p/fd/0" 2>/dev/null)" == "$tty" ]] && return
  done
  # mouse modes, focus events, bracketed paste off; leave the alternate screen; show the cursor
  printf '\e[?1000l\e[?1002l\e[?1003l\e[?1005l\e[?1006l\e[?1015l\e[?1004l\e[?2004l\e[?1049l\e[?25h' > "$tty"
  stty sane < "$tty" 2>/dev/null
  echo "$(stamp) reset terminal $tty" >> "$LOG"
}

# pid -> first time seen stuck, and its terminal, from earlier runs
declare -A first_seen tty_of
if [[ -f "$STATE" ]]; then
  while read -r pid t tty; do first_seen[$pid]=$t; tty_of[$pid]=$tty; done < "$STATE"
fi

# A process counts as python when it runs /usr/bin/python3*, whether started
# as python3, python3.12 or through a #! line.
is_python() {
  [[ "$(readlink "/proc/$1/exe" 2>/dev/null)" == /usr/bin/python3* ]]
}

declare -A still_stuck kind_of
for p in /proc/[0-9]*/stat; do
  read -r content < "$p" 2>/dev/null || continue
  pid="${p#/proc/}"; pid="${pid%/stat}"
  if [[ "$content" == *"(claude)"*" D "* ]]; then
    kind_of[$pid]=claude
  else
    # The state is the field after the name, which ends at the last ") ".
    state=${content##*) }
    [[ "${state%% *}" == D ]] || continue
    if is_python "$pid"; then kind_of[$pid]=python3; else kind_of[$pid]=other; fi
  fi
  if [[ "${kind_of[$pid]}" == other ]]; then
    # Logged once, when it has been stuck for GRACE seconds.
    since=${first_seen[$pid]:-$now}
    still_stuck[$pid]=$since
    # Marks the entry in the state file as one of these; reset_tty ignores it.
    tty_of[$pid]=other
    if (( now - since >= GRACE )) && [[ ! -f "$STATE_DIR/logged.$pid" ]]; then
      touch "$STATE_DIR/logged.$pid"
      echo "$(stamp) stuck pid=$pid for $(( now - since ))s name=$(cat "/proc/$pid/comm" 2>/dev/null) $(describe "$pid")" >> "$LOG"
      detail "$pid" >> "$LOG"
    fi
    continue
  fi
  if [[ -z "${first_seen[$pid]}" ]]; then
    still_stuck[$pid]=$now
    tty=$(readlink "/proc/$pid/fd/0" 2>/dev/null)
    # Only a claude's terminal is kept, since only a claude's gets reset.
    # TODO(claude): undecided: how a python3 entry is told apart once the
    # process has gone. Its terminal is left out of the state file, so
    # reset_tty skips it; the state file format is unchanged.
    [[ "${kind_of[$pid]}" == claude ]] && tty_of[$pid]=$tty
    echo "$(stamp) stuck pid=$pid tty=${tty:-?} $(describe "$pid")" >> "$LOG"
    detail "$pid" >> "$LOG"
  else
    still_stuck[$pid]=${first_seen[$pid]}
  fi
done

: > "$STATE.new"
for pid in "${!still_stuck[@]}"; do
  since=${still_stuck[$pid]}
  echo "$pid $since ${tty_of[$pid]}" >> "$STATE.new"
  stuck_for=$(( now - since ))
  [[ "${kind_of[$pid]}" == claude ]] || continue
  if (( stuck_for >= GRACE )); then
    # A D-state process only acts on SIGKILL once the kernel lets go, so this
    # repeats each run until it's gone; log the first send only.
    if [[ ! -f "$STATE_DIR/killed.$pid" ]]; then
      echo "$(stamp) killing pid=$pid after ${stuck_for}s $(describe "$pid")" >> "$LOG"
      touch "$STATE_DIR/killed.$pid"
    fi
    kill -9 "$pid" 2>/dev/null
  fi
done

# Pids no longer stuck: say how it ended, and forget them.
for pid in "${!first_seen[@]}"; do
  [[ -n "${still_stuck[$pid]}" ]] && continue
  if [[ -f "$STATE_DIR/logged.$pid" ]]; then
    rm -f "$STATE_DIR/logged.$pid"
    if [[ -d "/proc/$pid" ]]; then
      echo "$(stamp) recovered pid=$pid after $(( now - first_seen[$pid] ))s" >> "$LOG"
    else
      echo "$(stamp) exited pid=$pid while stuck" >> "$LOG"
    fi
    continue
  fi
  # Another process stuck for less than GRACE: nothing was logged, so say nothing.
  [[ "${tty_of[$pid]}" == other ]] && continue
  if [[ -f "$STATE_DIR/killed.$pid" ]]; then
    echo "$(stamp) gone pid=$pid" >> "$LOG"
    rm -f "$STATE_DIR/killed.$pid"
    reset_tty "${tty_of[$pid]}"
  elif [[ -d "/proc/$pid" ]]; then
    echo "$(stamp) recovered pid=$pid after $(( now - first_seen[$pid] ))s" >> "$LOG"
  else
    echo "$(stamp) exited pid=$pid while stuck" >> "$LOG"
    reset_tty "${tty_of[$pid]}"
  fi
done
mv "$STATE.new" "$STATE"
