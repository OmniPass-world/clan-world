#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/env.sh"

check() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "ok: $cmd -> $(command -v "$cmd")"
  else
    echo "missing: $cmd" >&2
    return 1
  fi
}

fail=0
check node || fail=1
check pnpm || fail=1
check forge || fail=1
check cast || fail=1
check solana || fail=1
check spl-token || fail=1
check ntt || fail=1

if [[ -f "$ENV_FILE" ]]; then
  echo "ok: found $ENV_FILE"
else
  echo "warning: no .env file found. Copy .env.template to .env before deployment."
fi

if [[ "$fail" -ne 0 ]]; then
  echo "One or more tools are missing." >&2
  exit 1
fi

echo "Doctor checks passed."
