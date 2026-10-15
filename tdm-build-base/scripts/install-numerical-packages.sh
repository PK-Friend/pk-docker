#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# Install foundational engines before their dependants. Each install gets a new
# R process so a namespace loaded by remotes cannot outlive a package replacement.
for package in rxode2ll rxode2 nlmixr2est nlmixr2 mrgsolve NonCompart; do
  Rscript --vanilla "$SCRIPT_DIR/numerical-packages.R" install "$package"
done

Rscript --vanilla "$SCRIPT_DIR/numerical-packages.R" verify
