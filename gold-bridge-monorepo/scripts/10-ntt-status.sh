#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/env.sh"
NTT_PROJECT_DIR="${NTT_PROJECT_DIR:-ntt}"
cd "$ROOT_DIR/$NTT_PROJECT_DIR"
ntt status
