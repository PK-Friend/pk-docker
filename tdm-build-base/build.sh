#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(dirname -- "$SCRIPT_DIR")
VERSION=$(cat "$SCRIPT_DIR/VERSION")
IMAGE="ghcr.io/pk-friend/pk-docker/tdm-build-base:${VERSION}"

if (($#)); then
  echo "Usage: $0 (build and verify; publish when CR_USER and CR_PAT are set)" >&2
  exit 2
fi
if [[ ! "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo "VERSION must be a numeric X.Y.Z version without leading zeros" >&2
  exit 2
fi

publish=false
if [[ -n "${CR_USER:-}" && -n "${CR_PAT:-}" ]]; then
  printf '%s\n' "$CR_PAT" | docker login ghcr.io -u "$CR_USER" --password-stdin
  GH_TOKEN="$CR_PAT" bash "$REPO_DIR/scripts/publish.sh" --check "$VERSION"
  publish=true
elif [[ -n "${CR_USER:-}" || -n "${CR_PAT:-}" ]]; then
  echo 'Set both CR_USER and CR_PAT to publish, or unset both to build locally.' >&2
  exit 2
else
  echo 'CR_USER and CR_PAT are unset; building and verifying locally without publishing.'
fi

# Match the deployed NKS architecture, including on Apple Silicon hosts.
docker buildx build --platform linux/amd64 --pull --load \
  --label "org.opencontainers.image.version=$VERSION" \
  -t "$IMAGE" "$SCRIPT_DIR"
docker run --rm --platform linux/amd64 --network none \
  -v "$REPO_DIR/tests/smoke.R:/tmp/smoke.R:ro" \
  "$IMAGE" Rscript --vanilla /tmp/smoke.R
echo "Verified local image: $IMAGE"

if [[ "$publish" == true ]]; then
  # Recheck registry state after the potentially long build, then publish this image.
  GH_TOKEN="$CR_PAT" bash "$REPO_DIR/scripts/publish.sh" "$VERSION" "$IMAGE"
fi
