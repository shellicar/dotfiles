#!/bin/sh
# Runs tmux-snapshot against a real tmux, one case per fresh container.
#
# Separate from tests/run.sh, which fakes tmux and can only show what the
# command decides. This shows what tmux does with it: that a restore rebuilds
# what a save recorded, and how tmux treats the arguments the command passes
# ('-s ""', ids as targets, names holding ':' or '.'). The container is what
# makes it safe: every server it starts, and every one it kills, is in there.
#
# Needs docker. A missing docker, or an image that will not build, exits 64; it
# never exits 0 for a run that did not happen.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
IMAGE=${IMAGE:-dotfiles-tmux-snapshot-test}

command -v docker >/dev/null 2>&1 || { echo "docker not found; these tests need it" >&2; exit 64; }

docker build -q -t "$IMAGE" "$HERE" >/dev/null || { echo "cannot build the test image" >&2; exit 64; }
version=$(docker run --rm "$IMAGE" tmux -V) || { echo "cannot run tmux in the test image" >&2; exit 64; }
printf 'running against %s\n' "$version"

failed=0
ran=0

for case_file in "$HERE"/cases/*.sh; do
  [ -f "$case_file" ] || continue
  ran=$((ran + 1))
  name=$(basename "$case_file" .sh)

  out=$(docker run --rm \
    -v "$REPO:/repo:ro" \
    -v "$HERE/lib.sh:/case/lib.sh:ro" \
    -v "$case_file:/case/run.sh:ro" \
    "$IMAGE" sh /case/run.sh 2>&1)
  status=$?

  case "$out" in
    *"PASS $name"*) ;;
    *) status=1 ;;
  esac

  if [ "$status" -ne 0 ]; then
    failed=$((failed + 1))
    printf 'FAIL %s\n' "$name"
    printf '%s\n' "$out" | sed 's/^/  /'
  else
    printf 'pass %s\n' "$name"
  fi
done

[ "$ran" -eq 0 ] && { echo "no cases found" >&2; exit 64; }

if [ "$failed" -ne 0 ]; then
  printf '\ntmux: %d of %d FAILED\n' "$failed" "$ran"
  exit 1
fi
printf 'tmux: %d passed\n' "$ran"
exit 0
