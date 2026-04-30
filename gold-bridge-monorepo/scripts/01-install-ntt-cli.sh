#!/usr/bin/env bash
set -euo pipefail
curl -fsSL https://raw.githubusercontent.com/wormhole-foundation/native-token-transfers/main/cli/install.sh | bash
ntt --version
