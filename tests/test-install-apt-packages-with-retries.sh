#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
INSTALLER="$SCRIPT_DIR/../tdm-build-base/scripts/install-apt-packages-with-retries.sh"

if [[ ! -f "$INSTALLER" ]]; then
  echo "Expected the APT package installer to exist: $INSTALLER" >&2
  exit 1
fi

TMP_DIR=$(mktemp -d)
trap 'rm -rf -- "$TMP_DIR"' EXIT
FAKE_BIN="$TMP_DIR/bin"
mkdir -p "$FAKE_BIN"

cat > "$FAKE_BIN/apt-get" <<'FAKE_APT_GET'
#!/usr/bin/env bash
set -euo pipefail

command_name=${1:?missing apt-get subcommand}
count_file="$APT_STATE_DIR/$command_name.count"
count=0
if [[ -f "$count_file" ]]; then
  read -r count < "$count_file"
fi
count=$((count + 1))
printf '%s\n' "$count" > "$count_file"
printf '%s\n' "$*" >> "$APT_CALL_LOG"

network_error() {
  echo 'W: Failed to fetch https://r2u.stat.illinois.edu/ubuntu/dists/jammy/InRelease Could not connect to r2u.stat.illinois.edu:443, connection timed out' >&2
}

case "$APT_SCENARIO:$command_name" in
  transient-update:update)
    if (( count <= 2 )); then
      network_error
      exit 0
    fi
    echo 'apt-get update succeeded'
    ;;
  transient-update:install)
    echo 'package installation succeeded'
    ;;
  transient-upgrade:update)
    echo 'apt-get update succeeded'
    ;;
  transient-upgrade:upgrade)
    if (( count <= 1 )); then
      echo 'Err:1 https://r2u.stat.illinois.edu/ubuntu jammy InRelease Could not connect, connection timed out' >&2
      exit 100
    fi
    echo 'package upgrade succeeded'
    ;;
  transient-upgrade:install)
    echo 'package installation succeeded'
    ;;
  always-transient-update:update)
    network_error
    exit 0
    ;;
  transient-install:update)
    echo 'apt-get update succeeded'
    ;;
  transient-install:install)
    if (( count <= 2 )); then
      echo 'Err:1 https://r2u.stat.illinois.edu/ubuntu jammy InRelease Could not connect, connection timed out' >&2
      exit 100
    fi
    echo 'package installation succeeded'
    ;;
  permanent-package-error:install)
    echo 'E: Unable to locate package r-cran-tictoc' >&2
    exit 100
    ;;
  permanent-package-error:update)
    echo 'apt-get update succeeded'
    ;;
  *)
    echo "Unexpected apt-get invocation for scenario $APT_SCENARIO: $*" >&2
    exit 99
    ;;
esac
FAKE_APT_GET

cat > "$FAKE_BIN/sleep" <<'FAKE_SLEEP'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "${1:?missing duration}" >> "$APT_SLEEP_LOG"
FAKE_SLEEP
chmod +x "$FAKE_BIN/apt-get" "$FAKE_BIN/sleep"

assert_count() {
  local command_name=$1 expected=$2 actual=0
  if [[ -f "$APT_STATE_DIR/$command_name.count" ]]; then
    read -r actual < "$APT_STATE_DIR/$command_name.count"
  fi
  if [[ "$actual" != "$expected" ]]; then
    echo "Expected $command_name to run $expected times, got $actual" >&2
    return 1
  fi
}

assert_sleep_schedule() {
  local expected=$1 actual
  actual=$(tr '\n' ' ' < "$APT_SLEEP_LOG")
  if [[ "$actual" != "$expected" ]]; then
    echo "Expected retry delays '$expected', got '$actual'" >&2
    return 1
  fi
}

reset_fixture() {
  local scenario=$1
  APT_STATE_DIR="$TMP_DIR/state-$scenario"
  mkdir -p "$APT_STATE_DIR"
  APT_CALL_LOG="$APT_STATE_DIR/calls.log"
  APT_SLEEP_LOG="$APT_STATE_DIR/sleeps.log"
  : > "$APT_CALL_LOG"
  : > "$APT_SLEEP_LOG"
  export APT_SCENARIO="$scenario" APT_STATE_DIR APT_CALL_LOG APT_SLEEP_LOG
}

run_installer() {
  local output_file=$1
  shift
  PATH="$FAKE_BIN:$PATH" bash "$INSTALLER" "$@" > "$output_file" 2>&1
}

TEST_PACKAGES=(r-cran-testthat r-cran-nlmixr2)

# apt-get update can return success despite warning that an index was unreachable.
# Two transient failures should be retried, then installation should proceed on attempt three.
reset_fixture transient-update
run_installer "$TMP_DIR/transient-update.log" "${TEST_PACKAGES[@]}"
assert_count update 3
assert_count install 1
assert_sleep_schedule '5 10 '

grep -Fq "install -y -qq --no-install-recommends ${TEST_PACKAGES[*]}" "$APT_CALL_LOG"

# Transient failures during Dockerfile package upgrades also restart the install attempt.
reset_fixture transient-upgrade
run_installer "$TMP_DIR/transient-upgrade.log" --upgrade locales r-cran-jsonlite
assert_count update 2
assert_count upgrade 2
assert_count install 1
assert_sleep_schedule '5 '
grep -Fq 'upgrade -y -qq --no-install-recommends' "$APT_CALL_LOG"
grep -Fq 'install -y -qq --no-install-recommends locales r-cran-jsonlite' "$APT_CALL_LOG"

# A transient failure during package installation restarts update + install.
reset_fixture transient-install
run_installer "$TMP_DIR/transient-install.log" "${TEST_PACKAGES[@]}"
assert_count update 3
assert_count install 3
assert_sleep_schedule '5 10 '

# A permanent missing-package error is not a connection failure and must fail fast.
reset_fixture permanent-package-error
set +e
run_installer "$TMP_DIR/permanent-package-error.log" "${TEST_PACKAGES[@]}"
status=$?
set -e
if [[ "$status" -ne 100 ]]; then
  echo "Expected a permanent missing-package error to return 100, got $status" >&2
  exit 1
fi
assert_count update 1
assert_count install 1
assert_sleep_schedule ''

# A persistent connection failure gets at most three total attempts (two retries).
reset_fixture always-transient-update
set +e
run_installer "$TMP_DIR/always-transient-update.log" "${TEST_PACKAGES[@]}"
status=$?
set -e
if [[ "$status" -eq 0 ]]; then
  echo 'Expected persistent repository failure to fail after three attempts' >&2
  exit 1
fi
assert_count update 3
assert_count install 0
assert_sleep_schedule '5 10 '

echo 'APT package installer retry tests passed'
