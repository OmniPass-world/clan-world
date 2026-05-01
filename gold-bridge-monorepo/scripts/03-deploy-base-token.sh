#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/env.sh"

require_var BASE_RPC_URL
require_var EVM_PRIVATE_KEY
require_var BASE_TOKEN_NAME
require_var BASE_TOKEN_SYMBOL
require_var EVM_INITIAL_MINTER

ZERO_ADDRESS="0x0000000000000000000000000000000000000000"
EVM_DEPLOYER_ADDRESS="$(cast wallet address --private-key "$EVM_PRIVATE_KEY")"
TIMELOCK_PROPOSER="${TIMELOCK_PROPOSER:-$EVM_DEPLOYER_ADDRESS}"
TIMELOCK_EXECUTOR="${TIMELOCK_EXECUTOR:-$ZERO_ADDRESS}"
TIMELOCK_ADMIN="${TIMELOCK_ADMIN:-$ZERO_ADDRESS}"
TIMELOCK_DELAY_SECONDS="${TIMELOCK_DELAY_SECONDS:-86400}"
ADMIN_SLOT="0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103"

mkdir -p "$ROOT_DIR/artifacts"
cd "$ROOT_DIR/packages/contracts"

deploy_output="$(forge create --broadcast \
  --rpc-url "$BASE_RPC_URL" \
  --private-key "$EVM_PRIVATE_KEY" \
  src/deploy/UpgradeableGoldDeployer.sol:UpgradeableGoldDeployer \
  --constructor-args \
    "$BASE_TOKEN_NAME" \
    "$BASE_TOKEN_SYMBOL" \
    "$EVM_INITIAL_MINTER" \
    "$TIMELOCK_PROPOSER" \
    "$TIMELOCK_EXECUTOR" \
    "$TIMELOCK_ADMIN" \
    "$TIMELOCK_DELAY_SECONDS" \
  | tee "$ROOT_DIR/artifacts/base-token-deploy.log")"

DEPLOYER_HELPER_ADDRESS="$(printf '%s\n' "$deploy_output" | sed -n 's/^Deployed to: //p' | tail -n 1)"
if [[ -z "$DEPLOYER_HELPER_ADDRESS" ]]; then
  echo "Could not parse UpgradeableGoldDeployer address from forge output." >&2
  exit 1
fi

for _ in {1..20}; do
  if [[ "$(cast code "$DEPLOYER_HELPER_ADDRESS" --rpc-url "$BASE_RPC_URL")" != "0x" ]]; then
    break
  fi
  sleep 3
done

if [[ "$(cast code "$DEPLOYER_HELPER_ADDRESS" --rpc-url "$BASE_RPC_URL")" == "0x" ]]; then
  echo "UpgradeableGoldDeployer has no code yet: $DEPLOYER_HELPER_ADDRESS" >&2
  exit 1
fi

BASE_TOKEN_ADDRESS="$(cast call "$DEPLOYER_HELPER_ADDRESS" "proxy()(address)" --rpc-url "$BASE_RPC_URL")"
BASE_TOKEN_IMPLEMENTATION_ADDRESS="$(cast call "$DEPLOYER_HELPER_ADDRESS" "implementation()(address)" --rpc-url "$BASE_RPC_URL")"
BASE_TIMELOCK_ADDRESS="$(cast call "$DEPLOYER_HELPER_ADDRESS" "timelock()(address)" --rpc-url "$BASE_RPC_URL")"
BASE_PROXY_ADMIN_ADDRESS="0x$(cast storage "$BASE_TOKEN_ADDRESS" "$ADMIN_SLOT" --rpc-url "$BASE_RPC_URL" | tail -c 41)"

{
  echo
  echo "Upgradeable Base GOLD deployment summary"
  echo "  helper: $DEPLOYER_HELPER_ADDRESS"
  echo "  proxy token: $BASE_TOKEN_ADDRESS"
  echo "  implementation: $BASE_TOKEN_IMPLEMENTATION_ADDRESS"
  echo "  timelock: $BASE_TIMELOCK_ADDRESS"
  echo "  proxy admin: $BASE_PROXY_ADMIN_ADDRESS"
  echo "  timelock proposer: $TIMELOCK_PROPOSER"
  echo "  timelock executor: $TIMELOCK_EXECUTOR"
  echo "  timelock admin: $TIMELOCK_ADMIN"
  echo "  timelock delay seconds: $TIMELOCK_DELAY_SECONDS"
} | tee -a "$ROOT_DIR/artifacts/base-token-deploy.log"

echo
echo "Copy these into .env:"
echo "BASE_TOKEN_ADDRESS=$BASE_TOKEN_ADDRESS"
echo "BASE_TOKEN_IMPLEMENTATION_ADDRESS=$BASE_TOKEN_IMPLEMENTATION_ADDRESS"
echo "BASE_TIMELOCK_ADDRESS=$BASE_TIMELOCK_ADDRESS"
echo "BASE_PROXY_ADMIN_ADDRESS=$BASE_PROXY_ADMIN_ADDRESS"
