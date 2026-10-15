#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PUBLISHER="$SCRIPT_DIR/../scripts/publish.sh"
TEST_TMP=$(mktemp -d)
trap 'rm -rf -- "$TEST_TMP"' EXIT
mkdir -p "$TEST_TMP/bin"

cat > "$TEST_TMP/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$GH_CALLS"
[[ "$#" == 5 && "$1" == api && "$2" == --paginate && "$3" == 'orgs/PK-Friend/packages/container/pk-docker%2Ftdm-build-base/versions' && "$4" == --jq && "$5" == '.[] | .metadata.container.tags[]' ]] || exit 99
case "$GH_SCENARIO" in
  success) printf '%s' "$EXISTING_TAGS" ;;
  404) printf '{"message":"Not Found"}\n'; echo 'gh: Not Found (HTTP 404)' >&2; exit 1 ;;
  403) echo 'gh: Forbidden (HTTP 403)' >&2; exit 1 ;;
  500) echo 'gh: Internal Server Error (HTTP 500)' >&2; exit 1 ;;
  network) echo 'dial tcp: connection refused' >&2; exit 1 ;;
  *) exit 99 ;;
esac
MOCK

cat > "$TEST_TMP/bin/docker" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$DOCKER_CALLS"
if [[ "$1" == push && "$FAIL_VERSION_PUSH" == 1 && "$2" != *:latest ]]; then
  exit 1
fi
MOCK
chmod +x "$TEST_TMP/bin/gh" "$TEST_TMP/bin/docker"

export PATH="$TEST_TMP/bin:$PATH"
export GH_CALLS="$TEST_TMP/gh-calls" DOCKER_CALLS="$TEST_TMP/docker-calls"
export GH_SCENARIO EXISTING_TAGS FAIL_VERSION_PUSH
IMAGE=ghcr.io/pk-friend/pk-docker/tdm-build-base

run_publisher() {
  local expected=$1
  shift
  : > "$GH_CALLS"
  : > "$DOCKER_CALLS"
  local status=0
  bash "$PUBLISHER" "$@" > "$TEST_TMP/output" 2>&1 || status=$?
  if [[ "$expected" == success && "$status" != 0 ]] || [[ "$expected" == failure && "$status" == 0 ]]; then
    echo "Unexpected publisher status $status for $* ($GH_SCENARIO)" >&2
    cat "$TEST_TMP/output" >&2
    exit 1
  fi
}

assert_calls() {
  printf '%s' "$1" > "$TEST_TMP/expected-calls"
  diff -u "$TEST_TMP/expected-calls" "$DOCKER_CALLS"
}

GH_SCENARIO=404 EXISTING_TAGS='' FAIL_VERSION_PUSH=0
run_publisher success 1.0.0 tdm-build-base:ci
assert_calls "tag tdm-build-base:ci $IMAGE:1.0.0
push $IMAGE:1.0.0
tag tdm-build-base:ci $IMAGE:latest
push $IMAGE:latest
"

GH_SCENARIO=success EXISTING_TAGS=$'latest\n1.0.0\n'
run_publisher failure 1.0.0 tdm-build-base:ci
assert_calls ''

for GH_SCENARIO in 403 500 network; do
  run_publisher failure 1.0.1 tdm-build-base:ci
  assert_calls ''
done

GH_SCENARIO=success EXISTING_TAGS=$'latest\n1.9.0\n'
run_publisher success 1.2.0 tdm-build-base:ci
assert_calls "tag tdm-build-base:ci $IMAGE:1.2.0
push $IMAGE:1.2.0
"

# Compare SemVer numerically; 1.10.0 is newer than 1.9.0.
run_publisher success 1.10.0 tdm-build-base:ci
assert_calls "tag tdm-build-base:ci $IMAGE:1.10.0
push $IMAGE:1.10.0
tag tdm-build-base:ci $IMAGE:latest
push $IMAGE:latest
"

FAIL_VERSION_PUSH=1
run_publisher failure 1.10.0 tdm-build-base:ci
assert_calls "tag tdm-build-base:ci $IMAGE:1.10.0
push $IMAGE:1.10.0
"

FAIL_VERSION_PUSH=0
for version in v1.0.0 01.0.0 1.0 1.0.0-dev latest; do
  run_publisher failure "$version" tdm-build-base:ci
  assert_calls ''
  [[ ! -s "$GH_CALLS" ]]
done
run_publisher failure
assert_calls ''
[[ ! -s "$GH_CALLS" ]]

printf 'GHCR publication policy tests passed\n'
