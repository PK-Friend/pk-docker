#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(dirname -- "$SCRIPT_DIR")
VERSION=$(cat "$SCRIPT_DIR/VERSION")
IMAGE="ghcr.io/pk-friend/pk-docker/tdm-build-base:${VERSION}"

if (($#)); then
  echo "Usage: $0 (build and verify locally; publishing runs in GitHub Actions)" >&2
  exit 2
fi
if [[ ! "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo "VERSION must be a numeric X.Y.Z version without leading zeros" >&2
  exit 2
fi

# Match the deployed NKS architecture, including on Apple Silicon hosts.
docker buildx build --platform linux/amd64 --pull --load \
  --label "org.opencontainers.image.version=$VERSION" \
  -t "$IMAGE" "$SCRIPT_DIR"
docker run --rm --platform linux/amd64 --network none \
  -v "$REPO_DIR/tests/smoke.R:/tmp/smoke.R:ro" \
  "$IMAGE" Rscript --vanilla /tmp/smoke.R
echo "Verified local image: $IMAGE"
