#!/usr/bin/env bash
set -euo pipefail

IMAGE=ghcr.io/pk-friend/pk-docker/tdm-build-base
STABLE_VERSION='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'

if [[ $# -ne 2 || ! "$1" =~ $STABLE_VERSION || -z "$2" ]]; then
  echo 'Usage: bash scripts/publish.sh X.Y.Z LOCAL_IMAGE (canonical numeric version required)' >&2
  exit 1
fi
version=$1
local_image=$2

publish_tmp=$(mktemp -d)
trap 'rm -rf -- "$publish_tmp"' EXIT

# The workflow authenticates gh and Docker and serializes all publications.
if ! gh api --paginate 'orgs/PK-Friend/packages/container/pk-docker%2Ftdm-build-base/versions' \
    --jq '.[] | .metadata.container.tags[]' \
    > "$publish_tmp/tags" 2> "$publish_tmp/error"; then
  if grep -Eq '^gh: .+ \(HTTP 404\)$' "$publish_tmp/error"; then
    # GHCR has no package entry before the first successful publication.
    : > "$publish_tmp/tags"
  else
    echo 'Cannot list existing GHCR tags; publication stopped.' >&2
    exit 1
  fi
fi

printf '%s\n' "$version" > "$publish_tmp/stable-tags"
while IFS= read -r existing || [[ -n "$existing" ]]; do
  if [[ "$existing" == "$version" ]]; then
    echo "Version $version already exists; refusing to overwrite it." >&2
    exit 1
  fi
  if [[ "$existing" =~ $STABLE_VERSION ]]; then
    printf '%s\n' "$existing" >> "$publish_tmp/stable-tags"
  fi
done < "$publish_tmp/tags"
newest=$(sort -V "$publish_tmp/stable-tags" | tail -n 1)

docker tag "$local_image" "$IMAGE:$version"
docker push "$IMAGE:$version"

if [[ "$version" == "$newest" ]]; then
  docker tag "$local_image" "$IMAGE:latest"
  docker push "$IMAGE:latest"
else
  echo "Published $version; latest stays on the newer release."
fi
