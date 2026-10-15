#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
VERSION=$(cat "$ROOT/tdm-build-base/VERSION")
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR/bin"
export DOCKER_CALLS="$TEST_DIR/docker-calls"
cat > "$TEST_DIR/bin/docker" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$DOCKER_CALLS"
if [[ "${FAIL_BUILD:-0}" == 1 && "$1" == buildx ]]; then exit 1; fi
MOCK
chmod +x "$TEST_DIR/bin/docker"
export PATH="$TEST_DIR/bin:$PATH"

# Invocation from outside the repository must still find the build context/test.
(cd "$TEST_DIR" && bash "$ROOT/tdm-build-base/build.sh")
grep -Fq 'buildx build --platform linux/amd64 --pull --load' "$DOCKER_CALLS"
grep -Fq "ghcr.io/pk-friend/pk-docker/tdm-build-base:$VERSION" "$DOCKER_CALLS"
grep -Fq 'run --rm --platform linux/amd64 --network none' "$DOCKER_CALLS"
if grep -Eq '(^| )(--push|login|push)( |$)' "$DOCKER_CALLS"; then
  echo 'Local build must not authenticate or publish' >&2; exit 1
fi

: > "$DOCKER_CALLS"
if FAIL_BUILD=1 bash "$ROOT/tdm-build-base/build.sh"; then
  echo 'Build failure was ignored' >&2; exit 1
fi
if grep -q '^run ' "$DOCKER_CALLS"; then
  echo 'Smoke test must not run after a failed build' >&2; exit 1
fi
if bash "$ROOT/tdm-build-base/build.sh" --push; then
  echo 'Unexpected arguments must be rejected' >&2; exit 1
fi
echo 'PASS: local build, architecture, offline smoke, failure propagation, no publishing'
