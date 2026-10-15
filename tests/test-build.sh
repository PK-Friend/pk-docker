#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
VERSION=$(cat "$ROOT/tdm-build-base/VERSION")
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR/bin"
export CALLS="$TEST_DIR/calls" GH_COUNT="$TEST_DIR/gh-count"
export IMAGE="ghcr.io/pk-friend/pk-docker/tdm-build-base:$VERSION"
export BUILD_CONTEXT="$ROOT/tdm-build-base" SMOKE_FILE="$ROOT/tests/smoke.R"
export EXPECTED_TOKEN='fake-test-only-token' VERSION SCENARIO

cat > "$TEST_DIR/bin/docker" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  login)
    [[ "$*" == 'login ghcr.io -u test-publisher --password-stdin' ]]
    IFS= read -r token
    [[ "$token" == "$EXPECTED_TOKEN" ]]
    printf 'login\n' >> "$CALLS"
    [[ "$SCENARIO" != login_failure ]]
    ;;
  buildx)
    [[ "$*" == "buildx build --platform linux/amd64 --pull --load --label org.opencontainers.image.version=$VERSION -t $IMAGE $BUILD_CONTEXT" ]]
    printf 'build %s\n' "$IMAGE" >> "$CALLS"
    [[ "$SCENARIO" != build_failure ]]
    ;;
  run)
    [[ "$*" == "run --rm --platform linux/amd64 --network none -v $SMOKE_FILE:/tmp/smoke.R:ro $IMAGE Rscript --vanilla /tmp/smoke.R" ]]
    printf 'smoke %s\n' "$IMAGE" >> "$CALLS"
    [[ "$SCENARIO" != smoke_failure ]]
    ;;
  tag|push) printf '%s\n' "$*" >> "$CALLS" ;;
  *) exit 99 ;;
esac
MOCK

cat > "$TEST_DIR/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[[ "$GH_TOKEN" == "$EXPECTED_TOKEN" ]]
[[ "$*" == 'api --paginate orgs/PK-Friend/packages/container/pk-docker%2Ftdm-build-base/versions --jq .[] | .metadata.container.tags[]' ]]
count=0
if [[ -f "$GH_COUNT" ]]; then read -r count < "$GH_COUNT"; fi
count=$((count + 1))
printf '%s\n' "$count" > "$GH_COUNT"
printf 'check %s\n' "$count" >> "$CALLS"
case "$SCENARIO:$count" in
  preflight_failure:1|recheck_failure:2) echo 'gh: Forbidden (HTTP 403)' >&2; exit 1 ;;
  existing_version:1|concurrent_version:2) printf '%s\n' "$VERSION" ;;
  *) echo 'gh: Not Found (HTTP 404)' >&2; exit 1 ;;
esac
MOCK
chmod +x "$TEST_DIR/bin/docker" "$TEST_DIR/bin/gh"
export PATH="$TEST_DIR/bin:$PATH"

run_build() {
  local expected=$1
  shift
  : > "$CALLS"
  rm -f "$GH_COUNT"
  local status=0
  # Outside-repo invocation must still resolve the context and smoke file.
  (cd "$TEST_DIR" && bash "$ROOT/tdm-build-base/build.sh" "$@") > "$TEST_DIR/output" 2>&1 || status=$?
  if [[ "$expected" == success && "$status" != 0 ]] || [[ "$expected" == failure && "$status" == 0 ]]; then
    echo "Unexpected build status $status ($SCENARIO)" >&2
    cat "$TEST_DIR/output" >&2
    exit 1
  fi
  if grep -Fq "$EXPECTED_TOKEN" "$TEST_DIR/output" "$CALLS"; then
    echo 'Credential appeared in output or command arguments' >&2
    exit 1
  fi
}

assert_calls() {
  printf '%s' "$1" > "$TEST_DIR/expected"
  diff -u "$TEST_DIR/expected" "$CALLS"
}

unset CR_USER CR_PAT
export GH_TOKEN=unrelated-token
SCENARIO=success
run_build success
assert_calls "build $IMAGE
smoke $IMAGE
"

export CR_USER=test-publisher
run_build failure
assert_calls ''
unset CR_USER
export CR_PAT="$EXPECTED_TOKEN"
run_build failure
assert_calls ''

export CR_USER=test-publisher
run_build success
REMOTE=ghcr.io/pk-friend/pk-docker/tdm-build-base
assert_calls "login
check 1
build $IMAGE
smoke $IMAGE
check 2
tag $IMAGE $IMAGE
push $IMAGE
tag $IMAGE $REMOTE:latest
push $REMOTE:latest
"

SCENARIO=login_failure
run_build failure
assert_calls 'login
'
for SCENARIO in preflight_failure existing_version; do
  run_build failure
  assert_calls 'login
check 1
'
done
SCENARIO=build_failure
run_build failure
assert_calls "login
check 1
build $IMAGE
"
SCENARIO=smoke_failure
run_build failure
assert_calls "login
check 1
build $IMAGE
smoke $IMAGE
"
for SCENARIO in recheck_failure concurrent_version; do
  run_build failure
  assert_calls "login
check 1
build $IMAGE
smoke $IMAGE
check 2
"
done

SCENARIO=success
run_build failure --push
assert_calls ''
echo 'PASS: local build/publication credentials, ordering, offline smoke, secret handling and failure propagation'
