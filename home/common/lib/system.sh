#!/bin/sh
#
# system.sh's logic, sourced by system.sh at the repo root, which sets SYS_REPO,
# OS and SYS_USER and calls system_plan_main.
#
# system/<feature>/ holds one feature's files at their real paths, and its
# platforms file names the OSes (get-os.sh's names) it is on for. Each file or
# symlink in a feature that is on is an item: system_analyse works out which
# state each item is in and every command that would bring it into line, once,
# into ROWS. --plan prints ROWS; the interactive list and the apply read the
# same ROWS, so what is shown is what runs.
#
# ROWS holds one item per line, TAB-separated:
#   feature  path  role  state  detail  owner  mode  diff  commands  label  restart
#     path      the live path, /etc/wsl.conf
#     role      file, sysctl, unit or link
#     state     missing, differs, owner, inactive, restart, insync or unknown;
#               the first that applies, in that order
#     detail    what is out of line, for the row; every state that applies
#     owner     wanted owner:group, - for a link
#     mode      wanted mode, four digits, - for a link
#     diff      a file holding the diff hunks, - when there is none
#     commands  every command the item needs, joined by US, - when none
#     label     what the row is called: the path, or the unit's name
#     restart   the restart the item needs before it takes effect, or -
#
# Diff files live in SYS_TMP, which system_tmp_open makes and its traps
# remove, so ROWS is good only while the process that built it runs.
#
# Every read of the machine goes through a function below (live_owner,
# live_mode, mtime_epoch, boot_epoch, and the sysctl and systemctl commands),
# and every live path is prefixed with LIVE_ROOT, so a test can stand in for
# the machine. GNU tools are assumed where noted: the features here are WSL
# only.

# The variables below are read by the command and by the tests, which the
# linter cannot see from inside this file.
# shellcheck disable=SC2034

SYS_TAB=$(printf '\t')
SYS_US=$(printf '\037')
SYS_NL='
'
LIVE_ROOT=''

if [ -t 1 ]; then
  SYS_ESC=$(printf '\033')
  BOLD="${SYS_ESC}[1m"; DIM="${SYS_ESC}[2m"; GREEN="${SYS_ESC}[0;32m"; RESET="${SYS_ESC}[0m"
  SYS_DIFF_COLOR=--color=always
else
  BOLD=''; DIM=''; GREEN=''; RESET=''
  SYS_DIFF_COLOR=--color=never
fi

# ── reading the machine ─────────────────────────────────────────────────────

# owner:group, as names. GNU stat.
live_owner() { # <path>
  stat -c '%U:%G' -- "$1"
}

# The mode as four octal digits. GNU stat.
live_mode() { # <path>
  local m
  m=$(stat -c '%a' -- "$1")
  while [ ${#m} -lt 4 ]; do m=0$m; done
  printf '%s\n' "$m"
}

# Seconds since the epoch the file was last modified. GNU stat.
mtime_epoch() { # <path>
  stat -c %Y -- "$1"
}

# Seconds since the epoch the kernel booted.
boot_epoch() {
  awk '$1 == "btime" { print $2 }' /proc/stat
}

# ── small helpers ───────────────────────────────────────────────────────────

# The argument as one shell word: as it is when it needs no quoting, otherwise
# single-quoted.
sys_q() { # <string>
  case $1 in
    '' | *[!A-Za-z0-9_./:=@%+,-]*)
      printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")" ;;
    *) printf '%s' "$1" ;;
  esac
}

# Appends the hunks of git's diff from <old> to <new> to <out>. Only the hunks:
# the header names the temporary files, which mean nothing to the reader.
sys_diff_files() { # <old> <new> <out>
  git --no-pager diff --no-index --no-ext-diff "$SYS_DIFF_COLOR" -- "$1" "$2" |
    sed -n '/@@/,$p' >> "$3"
}

# The same, for two texts that are not files: a sysctl value, a unit's state.
sys_diff_text() { # <old text> <new text> <out>
  printf '%s\n' "$1" > "$SYS_TMP/old"
  printf '%s\n' "$2" > "$SYS_TMP/new"
  sys_diff_files "$SYS_TMP/old" "$SYS_TMP/new" "$3"
}

# ── temporary files ─────────────────────────────────────────────────────────

# Makes SYS_TMP and removes it however the process ends. A shell killed by a
# signal does not run its EXIT trap, so each signal has its own.
system_tmp_open() {
  SYS_TMP=$(mktemp -d "${TMPDIR:-/tmp}/system.XXXXXX") || {
    echo "system.sh: cannot make a temporary directory" >&2
    return 1
  }
  trap 'system_tmp_close' EXIT
  trap 'system_tmp_close; exit 129' HUP
  trap 'system_tmp_close; exit 130' INT
  trap 'system_tmp_close; exit 131' QUIT
  trap 'system_tmp_close; exit 143' TERM
}

system_tmp_close() {
  [ -n "${SYS_TMP:-}" ] && rm -rf "$SYS_TMP"
  SYS_TMP=''
}

# ── what the repo says ──────────────────────────────────────────────────────

# FEATURES_ALL and FEATURES_ON: feature names, one per line, every feature and
# the ones whose platforms file names $OS. A feature with no platforms file is
# on for nothing.
system_features() {
  FEATURES_ALL='' FEATURES_ON=''
  for d in "$SYS_REPO"/system/*/; do
    [ -d "$d" ] || continue
    f=${d%/}; f=${f##*/}
    FEATURES_ALL="$FEATURES_ALL$f$SYS_NL"
    [ -f "$d/platforms" ] || continue
    awk -v os="$OS" '{ gsub(/^[ \t]+|[ \t\r]+$/, "") } $0 == os { found = 1 } END { exit !found }' \
      "$d/platforms" && FEATURES_ON="$FEATURES_ON$f$SYS_NL"
  done
}

# ITEMS: one line per item in the features that are on, feature TAB path
# within the feature, sorted within each feature.
system_items() {
  ITEMS=''
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    ITEMS="$ITEMS$(cd "$SYS_REPO/system/$f" && find . \( -type f -o -type l \) ! -path ./platforms |
      sed 's|^\./||' | LC_ALL=C sort | awk -v f="$f" -v t="$SYS_TAB" '{ print f t $0 }')$SYS_NL"
  done <<EOF
$FEATURES_ON
EOF
}

# WANTED: one line per regular-file item, repo path TAB owner TAB mode.
#
# The rule: root:root, and 0755 or 0644 from git's executable bit, unless
# system/.gitattributes sets owner= or mode= for the path. Both come from one
# call each to git, for every item at once.
system_wanted() {
  WANTED=''
  set --
  while IFS="$SYS_TAB" read -r f rel; do
    [ -n "$f" ] || continue
    [ -L "$SYS_REPO/system/$f/$rel" ] && continue
    set -- "$@" "system/$f/$rel"
  done <<EOF
$ITEMS
EOF
  [ $# -gt 0 ] || return 0

  # path TAB mode, as git's index records it.
  index=$(git -C "$SYS_REPO" ls-files -s -z -- system/ | tr '\0' '\n' |
    awk -v t="$SYS_TAB" '{ split($0, a, "\t"); split(a[1], m, " "); print a[2] t m[1] }')
  # path TAB attr TAB value, for owner and mode.
  attrs=$(git -C "$SYS_REPO" check-attr -z owner mode -- "$@" | tr '\0' '\n' |
    awk -v t="$SYS_TAB" '{ p = $0; getline a; getline v; print p t a t v }')

  for p in "$@"; do
    owner=root:root
    imode=$(printf '%s\n' "$index" | awk -F"$SYS_TAB" -v p="$p" '$1 == p { print $2; exit }')
    # TODO(claude): undecided: where the executable bit of a file git does not
    # track yet comes from. The file's own bit on disk for now.
    if [ -z "$imode" ]; then
      if [ -x "$SYS_REPO/$p" ]; then imode=100755; else imode=100644; fi
    fi
    if [ "$imode" = 100755 ]; then mode=0755; else mode=0644; fi
    a_owner=$(printf '%s\n' "$attrs" | awk -F"$SYS_TAB" -v p="$p" '$1 == p && $2 == "owner" { print $3; exit }')
    a_mode=$(printf '%s\n' "$attrs" | awk -F"$SYS_TAB" -v p="$p" '$1 == p && $2 == "mode" { print $3; exit }')
    case $a_owner in
      '' | unspecified | set | unset) ;;
      # TODO(claude): undecided: what owner= without a group means. The group
      # is the same name as the owner for now.
      *:*) owner=$a_owner ;;
      *) owner=$a_owner:$a_owner ;;
    esac
    case $a_mode in
      '' | unspecified | set | unset) ;;
      # Padded as text: printf would read a leading 0 as octal.
      *) mode=$a_mode
         while [ ${#mode} -lt 4 ]; do mode=0$mode; done ;;
    esac
    WANTED="$WANTED$p$SYS_TAB$owner$SYS_TAB$mode$SYS_NL"
  done
}

# ── one item ────────────────────────────────────────────────────────────────

# The role decides which "in effect" check an item gets, from where it lives.
sys_role() { # <path within the feature>
  case $1 in
    */systemd/system/*.service | */systemd/system/*.socket | */systemd/system/*.timer | \
    */systemd/system/*.mount | */systemd/system/*.automount | */systemd/system/*.path | \
    */systemd/system/*.target | */systemd/system/*.swap | */systemd/system/*.slice)
      echo unit ;;
    etc/sysctl.conf | */sysctl.d/*.conf) echo sysctl ;;
    *) echo file ;;
  esac
}

# The restart a file needs before a change to it takes effect, or nothing.
# TODO(claude): undecided: which items need a restart, and how one that has not
# had it is told apart. Only /etc/wsl.conf, with wsl --shutdown, for now; it
# needs one when it was changed after the kernel booted.
sys_restart_for() { # <live path>
  case $1 in
    /etc/wsl.conf) echo 'wsl --shutdown' ;;
  esac
}

# Records a state the item is in. The first one recorded is the row's state;
# every one recorded goes into its detail.
sys_note() { # <state> <detail>
  [ -n "$I_STATE" ] || I_STATE=$1
  I_DETAIL="$I_DETAIL${I_DETAIL:+; }$2"
}

sys_cmd() { # <command>
  I_CMDS="$I_CMDS${I_CMDS:+$SYS_US}$1"
}

# A command for each directory above <path> the machine lacks, top down.
sys_parent_dirs() { # <live path>
  local d dirs
  d=${1%/*} dirs=''
  while [ -n "$d" ] && [ ! -e "$LIVE_ROOT$d" ]; do
    dirs="$d$SYS_NL$dirs"
    d=${d%/*}
  done
  while IFS= read -r d; do
    [ -n "$d" ] && sys_cmd "sudo install -d -o root -g root -m 0755 $(sys_q "$d")"
  done <<EOF
$dirs
EOF
}

# Works out one item and appends its row to ROWS.
system_analyse_item() { # <feature> <path within the feature>
  local f rel src path live role want owner mode o g changed unit w have
  local install_cmd have_owner have_mode what label
  f=$1 rel=$2
  src=$SYS_REPO/system/$f/$rel
  path=/$rel
  live=$LIVE_ROOT$path
  role=$(sys_role "$rel")
  I_STATE='' I_DETAIL='' I_CMDS='' I_RESTART=$(sys_restart_for "$path")
  I_DIFF=$SYS_TMP/diff.$ITEM_N
  : > "$I_DIFF"
  changed=no
  owner=- mode=-
  unit=${rel##*/}

  if [ -L "$src" ]; then
    # A symlink, such as a masked unit (a link to /dev/null). Owner and mode
    # do not apply to one.
    want=$(readlink "$src")
    if [ -L "$live" ]; then
      have=$(readlink "$live")
      if [ "$have" != "$want" ]; then
        sys_note differs "links to $have, want $want"
        sys_diff_text "-> $have" "-> $want" "$I_DIFF"
        sys_cmd "sudo ln -sfn $(sys_q "$want") $(sys_q "$path")"
        changed=yes
      fi
    elif [ -e "$live" ]; then
      sys_note differs "not a symlink, want one to $want"
      sys_diff_text "(not a symlink)" "-> $want" "$I_DIFF"
      sys_cmd "sudo ln -sfn $(sys_q "$want") $(sys_q "$path")"
      changed=yes
    else
      sys_note missing missing
      sys_diff_text "(missing)" "-> $want" "$I_DIFF"
      sys_parent_dirs "$path"
      sys_cmd "sudo ln -s $(sys_q "$want") $(sys_q "$path")"
      changed=yes
    fi
    # TODO(claude): undecided: whether a masked unit that is still running is
    # out of line. A link item gets a daemon-reload when it changes, and no
    # check of the unit's state.
    [ "$role" = unit ] && [ "$changed" = yes ] && sys_cmd 'sudo systemctl daemon-reload'
    role='link'
  else
    w=$(printf '%s\n' "$WANTED" | awk -F"$SYS_TAB" -v p="system/$f/$rel" '$1 == p { print $2 "\t" $3; exit }')
    owner=${w%"$SYS_TAB"*} mode=${w#*"$SYS_TAB"}
    o=$(sys_q "${owner%%:*}") g=$(sys_q "${owner#*:}")

    # The file as it should be on this machine, with {{user}} filled in.
    want=$SYS_TMP/want.$ITEM_N
    sed "s/{{user}}/$SYS_USER/g" "$src" > "$want"
    if grep -qF '{{user}}' "$src"; then
      install_cmd="sed $(sys_q "s/{{user}}/$SYS_USER/g") $(sys_q "$src") | sudo install -o $o -g $g -m $(sys_q "$mode") /dev/stdin $(sys_q "$path")"
    else
      install_cmd="sudo install -o $o -g $g -m $(sys_q "$mode") $(sys_q "$src") $(sys_q "$path")"
    fi

    if [ ! -e "$live" ] && [ ! -L "$live" ]; then
      sys_note missing missing
      sys_diff_files /dev/null "$want" "$I_DIFF"
      sys_parent_dirs "$path"
      sys_cmd "$install_cmd"
      changed=yes
    elif [ -L "$live" ] || [ ! -f "$live" ]; then
      sys_note differs "not a regular file"
      sys_cmd "$install_cmd"
      changed=yes
    elif [ ! -r "$live" ]; then
      # TODO(claude): undecided: how a file that cannot be read without root
      # is compared. It is not: the item is unavailable, and --plan does not
      # ask for root.
      sys_note unknown "cannot be read without root"
    elif ! cmp -s "$live" "$want"; then
      sys_note differs 'content differs'
      sys_diff_files "$live" "$want" "$I_DIFF"
      sys_cmd "$install_cmd"
      changed=yes
    else
      have_owner=$(live_owner "$live")
      have_mode=$(live_mode "$live")
      what=''
      if [ "$have_owner" != "$owner" ]; then
        what="owner $have_owner, want $owner"
        sys_cmd "sudo chown $(sys_q "$owner") $(sys_q "$path")"
      fi
      if [ "$have_mode" != "$mode" ]; then
        what="$what${what:+, }mode $have_mode, want $mode"
        sys_cmd "sudo chmod $(sys_q "$mode") $(sys_q "$path")"
      fi
      if [ -n "$what" ]; then
        sys_note owner "$what"
        sys_diff_text "owner $have_owner${SYS_NL}mode $have_mode" "owner $owner${SYS_NL}mode $mode" "$I_DIFF"
      fi
    fi
  fi

  if [ "$I_STATE" != unknown ]; then
    case $role in
      sysctl) system_check_sysctl "$path" "$want" ;;
      unit) system_check_unit "$unit" "$want" "$changed" ;;
    esac
  fi

  if [ -n "$I_RESTART" ] && [ -z "$I_STATE" ]; then
    if [ "$(mtime_epoch "$live")" -gt "$(boot_epoch)" ]; then
      sys_note restart "in sync, not in effect until WSL restarts: $I_RESTART"
    fi
  fi

  [ -n "$I_STATE" ] || I_STATE=insync
  [ -s "$I_DIFF" ] || I_DIFF=-
  # Only new content needs the restart; an owner or mode fix does not.
  [ "$changed" = yes ] || [ "$I_STATE" = restart ] || I_RESTART=''
  [ -n "$I_RESTART" ] || I_RESTART=-
  [ -n "$I_DETAIL" ] || I_DETAIL=-
  [ -n "$I_CMDS" ] || I_CMDS=-
  label=$path
  # TODO(claude): undecided: whether a unit that is only not in effect is a
  # row of its own. It is the file's row, named by the unit, for now.
  [ "$I_STATE" = inactive ] && [ "$role" = unit ] && label=$unit
  ROWS="$ROWS$f$SYS_TAB$path$SYS_TAB$role$SYS_TAB$I_STATE$SYS_TAB$I_DETAIL$SYS_TAB$owner$SYS_TAB$mode$SYS_TAB$I_DIFF$SYS_TAB$I_CMDS$SYS_TAB$label$SYS_TAB$I_RESTART$SYS_NL"
}

# Each key = value in a sysctl file, against the value the kernel has now.
system_check_sysctl() { # <live path> <wanted file>
  local key val have wl hl differ
  wl='' hl='' differ=no
  # key TAB value, for each setting: comments and blank lines dropped, the
  # leading - (ignore a failure) taken off the key, runs of blanks in the
  # value made one space.
  while IFS="$SYS_TAB" read -r key val; do
    [ -n "$key" ] || continue
    have=$(sysctl -n "$key" 2>/dev/null | tr '\t' ' ' | tr -s ' ')
    [ -n "$have" ] || have='(cannot be read)'
    [ "$have" = "$val" ] || differ=yes
    wl="$wl$key = $val$SYS_NL"
    hl="$hl$key = $have$SYS_NL"
  done <<EOF
$(awk -v t="$SYS_TAB" '
  { sub(/\r$/, "") }
  /^[ \t]*([#;]|$)/ { next }
  index($0, "=") == 0 { next }
  {
    k = substr($0, 1, index($0, "=") - 1); v = substr($0, index($0, "=") + 1)
    gsub(/^[ \t]+|[ \t]+$/, "", k); sub(/^-/, "", k)
    gsub(/^[ \t]+|[ \t]+$/, "", v); gsub(/[ \t]+/, " ", v)
    print k t v
  }' "$2")
EOF
  [ "$differ" = yes ] || return 0
  sys_note inactive 'not loaded'
  sys_diff_text "${hl%"$SYS_NL"}" "${wl%"$SYS_NL"}" "$I_DIFF"
  sys_cmd "sudo sysctl -p $(sys_q "$1")"
}

# A unit with an [Install] section is meant to be enabled and running.
system_check_unit() { # <unit> <wanted file> <changed: yes|no>
  local en ac err what
  [ "$3" = yes ] && sys_cmd 'sudo systemctl daemon-reload'
  # TODO(claude): undecided: what is expected of a unit with no [Install]
  # section, such as a service its timer starts. Nothing: it is not checked
  # for being enabled or running.
  grep -q '^\[Install\]' "$2" || return 0

  if [ "$I_STATE" = missing ]; then
    sys_cmd "sudo systemctl enable --now $(sys_q "$1")"
    return 0
  fi

  # Read from what systemctl prints, not its exit status: is-active exits
  # non-zero for a unit that is not running, and both fail with nothing
  # printed when systemd cannot be reached.
  en=$(systemctl is-enabled "$1" 2>"$SYS_TMP/err")
  ac=$(systemctl is-active "$1" 2>>"$SYS_TMP/err")
  if [ -z "$en" ] || [ -z "$ac" ]; then
    err=$(head -n 1 "$SYS_TMP/err")
    # TODO(claude): undecided: what a unit whose state systemctl cannot report
    # shows. Unavailable, when nothing else is out of line, with what systemctl
    # said.
    sys_note unknown "cannot tell if enabled or running: ${err:-systemctl printed nothing}"
    return 0
  fi

  what=''
  if [ "$en" != enabled ] && [ "$ac" != active ]; then
    what='not enabled, not running'
    sys_cmd "sudo systemctl enable --now $(sys_q "$1")"
  elif [ "$en" != enabled ]; then
    what='not enabled'
    sys_cmd "sudo systemctl enable $(sys_q "$1")"
    [ "$3" = yes ] && sys_cmd "sudo systemctl restart $(sys_q "$1")"
  elif [ "$ac" != active ]; then
    what='not running'
    sys_cmd "sudo systemctl start $(sys_q "$1")"
  elif [ "$3" = yes ]; then
    sys_cmd "sudo systemctl restart $(sys_q "$1")"
  fi
  [ -n "$what" ] || return 0
  sys_note inactive "$what"
  sys_diff_text "is-enabled $en${SYS_NL}is-active $ac" "is-enabled enabled${SYS_NL}is-active active" "$I_DIFF"
}

# ── every item ──────────────────────────────────────────────────────────────

# ROWS for every item in the features on for $OS, and the counts the header
# shows. Needs SYS_TMP.
system_analyse() {
  ROWS=''
  ITEM_N=0
  system_wanted
  while IFS="$SYS_TAB" read -r f rel; do
    [ -n "$f" ] || continue
    ITEM_N=$((ITEM_N + 1))
    system_analyse_item "$f" "$rel"
  done <<EOF
$ITEMS
EOF
}

# ── the printout ────────────────────────────────────────────────────────────

# IC: the icon for a state.
sys_icon() { # <state>
  case $1 in
    missing) IC='🆕' ;;
    differs) IC='✏️' ;;
    owner) IC='🔐' ;;
    inactive) IC='💤' ;;
    restart) IC='⚠️' ;;
    insync) IC='✓' ;;
    # TODO(claude): undecided: the icon for an item that cannot be worked out.
    *) IC='❔' ;;
  esac
}

# Whether a state is a row on the list: out of line, or cannot be told.
sys_is_row() { # <state>
  case $1 in insync | restart) return 1 ;; esac
  return 0
}

# One row: its box, its state's icon, its label and what is out of line.
# The box is [x] for an item that can run and [-] for one that cannot; the
# list will add [ ] for one that is unticked.
system_row_line() { # <state> <label> <detail> <label width>
  local box
  if [ "$1" = unknown ]; then box="${DIM}[-]${RESET}"; else box="${GREEN}[x]${RESET}"; fi
  sys_icon "$1"
  printf '%s %s %-*s  %s\n' "$box" "$IC" "$4" "$2" "$3"
}

# What a row will do: the path with its wanted owner and mode, the diff, and
# the commands, each line prefixed with <indent>.
system_preview() { # <row> <indent>
  local f path role state detail owner mode diff cmds label restart
  IFS="$SYS_TAB" read -r f path role state detail owner mode diff cmds label restart <<EOF
$1
EOF
  if [ "$owner" = - ]; then
    printf '%s%s\n' "$2" "$path"
  else
    printf '%s%s  %s %s\n' "$2" "$path" "$owner" "$mode"
  fi
  [ "$diff" = - ] || sed "s/^/$2/" "$diff"
  if [ "$cmds" != - ]; then
    printf '%swill run:\n' "$2"
    printf '%s\n' "$cmds" | tr "$SYS_US" '\n' | sed "s/^/$2  /"
  fi
  if [ "$restart" != - ] && [ "$cmds" != - ]; then
    printf '%sthen restart for it to take effect: %s (not run)\n' "$2" "$restart"
  fi
  return 0
}

# --plan's printout, from ROWS: the header, the items in sync and the ones that
# need a restart, then each row under its feature with its preview beneath it.
system_print_plan() {
  local nrows width f path role state detail owner mode diff cmds label restart last
  nrows=0 width=0
  while IFS="$SYS_TAB" read -r f path role state detail owner mode diff cmds label restart; do
    [ -n "$f" ] || continue
    sys_is_row "$state" || continue
    nrows=$((nrows + 1))
    [ ${#label} -gt "$width" ] && width=${#label}
  done <<EOF
$ROWS
EOF
  printf '  comparing with the machine ... %s out of line\n' "$nrows"

  if printf '%s' "$ROWS" | awk -F"$SYS_TAB" '$4 == "insync" { f = 1 } END { exit !f }'; then
    printf '\n%bIn sync%b\n' "$BOLD" "$RESET"
    while IFS="$SYS_TAB" read -r f path role state detail owner mode diff cmds label restart; do
      [ "$state" = insync ] || continue
      printf '  ✓ %s  %b[%s]%b\n' "$path" "$DIM" "$f" "$RESET"
    done <<EOF
$ROWS
EOF
  fi

  if printf '%s' "$ROWS" | awk -F"$SYS_TAB" '$4 == "restart" { f = 1 } END { exit !f }'; then
    printf '\n%bNeeds a restart%b\n' "$BOLD" "$RESET"
    while IFS="$SYS_TAB" read -r f path role state detail owner mode diff cmds label restart; do
      [ "$state" = restart ] || continue
      printf '  ⚠️ %s  %b[%s]%b  %s\n' "$path" "$DIM" "$f" "$RESET" "$detail"
    done <<EOF
$ROWS
EOF
  fi

  if [ "$nrows" -gt 0 ]; then
    printf '\n%b%s%b  %b[x] runs, [ ] does not, [-] unavailable%b\n' "$BOLD" "$OS" "$RESET" "$DIM" "$RESET"
    last=''
    while IFS= read -r row; do
      [ -n "$row" ] || continue
      IFS="$SYS_TAB" read -r f path role state detail owner mode diff cmds label restart <<EOF
$row
EOF
      sys_is_row "$state" || continue
      [ "$f" = "$last" ] || printf '%b%s%b\n' "$BOLD" "$f" "$RESET"
      last=$f
      printf '   '
      system_row_line "$state" "$label" "$detail" "$width"
      system_preview "$row" '       '
    done <<EOF
$ROWS
EOF
  fi
  printf '\n%bplan only, nothing was touched%b\n' "$DIM" "$RESET"
}

# ── --plan ──────────────────────────────────────────────────────────────────

system_plan_main() {
  local nf ni non
  system_features
  system_items
  nf=$(printf '%s' "$FEATURES_ALL" | grep -c .)
  non=$(printf '%s' "$FEATURES_ON" | grep -c .)
  ni=$(printf '%s' "$ITEMS" | grep -c .)
  printf '%bsystem.sh%b\n' "$BOLD" "$RESET"
  printf '%s · %s features · %s items\n' "$OS" "$non" "$ni"
  printf '  reading features ... %s of %s on for %s\n' "$non" "$nf" "$OS"
  system_tmp_open || exit 1
  system_analyse
  system_print_plan
  system_tmp_close
  trap - EXIT HUP INT QUIT TERM
}
