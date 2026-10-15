#!/usr/bin/env bash
set -euo pipefail

MAX_ATTEMPTS=3
RETRY_DELAY_BASE_SECONDS=5
TRANSIENT_REPOSITORY_ERROR='could not connect|connection timed out|temporary failure resolving|could not resolve|network is unreachable|connection reset by peer|failed to connect|no route to host|connection refused'

usage() {
  echo "Usage: $0 [--upgrade] package [package ...]" >&2
  exit 2
}

upgrade_packages=false
if [[ "${1:-}" == --upgrade ]]; then
  upgrade_packages=true
  shift
fi

(($# > 0)) || usage
packages=("$@")

run_apt_command() {
  local output_file status
  output_file=$(mktemp)

  if apt-get "$@" >"$output_file" 2>&1; then
    status=0
  else
    status=$?
  fi

  if grep -Eiq "$TRANSIENT_REPOSITORY_ERROR" "$output_file"; then
    cat "$output_file" >&2
    rm -f -- "$output_file"
    return 75
  fi

  if (( status != 0 )); then
    cat "$output_file" >&2
    rm -f -- "$output_file"
    return "$status"
  fi

  cat "$output_file"
  rm -f -- "$output_file"
  return 0
}

attempt=1
while true; do
  if run_apt_command update -qq; then
    apt_status=0
    if [[ "$upgrade_packages" == true ]]; then
      if run_apt_command upgrade -y -qq --no-install-recommends; then
        :
      else
        apt_status=$?
      fi
    fi

    if (( apt_status == 0 )); then
      if run_apt_command install -y -qq --no-install-recommends "${packages[@]}"; then
        :
      else
        apt_status=$?
      fi
    fi
  else
    apt_status=$?
  fi

  if (( apt_status == 0 )); then
    exit 0
  fi
  if (( apt_status != 75 )); then
    exit "$apt_status"
  fi

  if (( attempt >= MAX_ATTEMPTS )); then
    echo "APT dependency installation failed after $MAX_ATTEMPTS attempts" >&2
    exit 1
  fi

  delay=$((RETRY_DELAY_BASE_SECONDS * (2 ** (attempt - 1))))
  attempt=$((attempt + 1))
  echo "Transient package repository connection error; retry $((attempt - 1))/$((MAX_ATTEMPTS - 1)) in ${delay}s" >&2
  sleep "$delay"
done
