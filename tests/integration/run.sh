#!/bin/sh
# Runs each scenario in a container against a real repository.
#
# Separate from tests/run.sh on purpose. That suite builds no repository and is
# fast enough to run on every change; this one needs docker and exists to cover
# the half that acts: run_plan, remove_branch against a real worktree, and a
# real rescue rebase. Nothing else ever runs those.
#
# The container is why this is safe to run at all: it deletes branches and
# worktrees for real, and none of them are yours.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
IMAGE=${IMAGE:-alpine/git:latest}

command -v docker >/dev/null 2>&1 || {
  echo "docker not found; skipping the integration scenarios" >&2
  exit 0
}

failed=0
ran=0

for scenario in "$HERE"/scenarios/*.sh; do
  [ -f "$scenario" ] || continue
  ran=$((ran + 1))
  name=$(basename "$scenario" .sh)

  # shasum is what content_hash uses and alpine does not ship it; sha1sum is the
  # same algorithm and the same first field, so a shim keeps the command honest
  # without changing it for a test.
  out=$(docker run --rm --entrypoint sh \
    -v "$REPO:/repo:ro" \
    -v "$HERE/lib.sh:/scenario/lib.sh:ro" \
    -v "$scenario:/scenario/run.sh:ro" \
    "$IMAGE" -c 'printf "#!/bin/sh\nexec sha1sum \"\$@\"\n" > /usr/local/bin/shasum && chmod +x /usr/local/bin/shasum && exec sh /scenario/run.sh' 2>&1)
  status=$?

  case "$out" in
    *"PASS $name"*) ;;
    *) status=1 ;;
  esac

  if [ "$status" -ne 0 ]; then
    failed=$((failed + 1))
    printf 'FAIL %s\n' "$name"
    printf '%s\n' "$out" | sed 's/^/  /'
  fi
done

[ "$ran" -eq 0 ] && { echo "no scenarios found" >&2; exit 64; }

if [ "$failed" -ne 0 ]; then
  printf '\nintegration: %d of %d FAILED\n' "$failed" "$ran"
  exit 1
fi
printf 'integration: %d passed\n' "$ran"
exit 0
