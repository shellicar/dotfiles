#!/bin/sh
# Runs system.sh against real files owned by root, one case per fresh
# container.
#
# Separate from tests/run.sh, which stands in for the machine and can only
# show what the command decides from what it is told. This shows what it reads
# from real files: a root-owned file in sync, a file owned by someone else, a
# sudoers file whose mode comes from the real git reading system/.gitattributes,
# run as an ordinary user, and what it leaves behind when interrupted. The
# container is what makes it safe: every file it sets up is in there.
#
# Needs docker. A missing docker, or an image that will not build, exits 64; it
# never exits 0 for a run that did not happen.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
IMAGE=${IMAGE:-dotfiles-system-test}

command -v docker >/dev/null 2>&1 || { echo "docker not found; these tests need it" >&2; exit 64; }

docker build -q -t "$IMAGE" "$HERE" >/dev/null || { echo "cannot build the test image" >&2; exit 64; }

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
  printf '\nsystem: %d of %d FAILED\n' "$failed" "$ran"
  exit 1
fi
printf 'system: %d passed\n' "$ran"
exit 0
