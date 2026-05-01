import {
  ContractFunctionRevertedError,
  createPublicClient,
  createWalletClient,
  http,
  type Account,
  type PublicClient,
  type WalletClient,
} from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { baseSepolia, CLAN_WORLD_ABI } from '@clan-world/shared/adapters';
import {
  HeartbeatRateLimitedError,
  type IHeartbeatCaller,
} from '@clan-world/agents/seams';

export interface RunnerHeartbeatConfig {
  /** Hex-encoded 64-char private key, optionally 0x-prefixed. */
  privateKey: string;
  /** Override RPC URL; defaults to the Base Sepolia public endpoint. */
  rpcUrl?: string;
  /** ClanWorld contract address. */
  contractAddress: `0x${string}`;
}

/**
 * Reads `RUNNER_PRIVATE_KEY`, `RPC_URL_PRIMARY`, `CLAN_WORLD_CONTRACT_ADDRESS`
 * from env. Throws if `RUNNER_PRIVATE_KEY` is missing — the runner intentionally
 * does not generate or store its own wallet; provisioning is operator-side.
 */
export function configFromEnv(env: NodeJS.ProcessEnv = process.env): RunnerHeartbeatConfig {
  const pk = env['RUNNER_PRIVATE_KEY'];
  if (!pk) {
    throw new Error(
      'RUNNER_PRIVATE_KEY is not set — the runner needs a dedicated wallet (NEVER reuse an Elder wallet). ' +
        'Provision a fresh key, fund it with testnet ETH, and export RUNNER_PRIVATE_KEY before starting the daemon.',
    );
  }
  const contractAddress = env['CLAN_WORLD_CONTRACT_ADDRESS'];
  if (!contractAddress || !/^0x[0-9a-fA-F]{40}$/.test(contractAddress)) {
    throw new Error(
      `CLAN_WORLD_CONTRACT_ADDRESS missing or invalid; expected 0x-prefixed 40-hex-char address, got ${String(contractAddress)}`,
    );
  }
  return {
    privateKey: pk,
    rpcUrl: env['RPC_URL_PRIMARY'] || env['RPC_URL_FALLBACK'],
    contractAddress: contractAddress as `0x${string}`,
  };
}

/**
 * Viem-backed `IHeartbeatCaller`. Wallet account is the dedicated runner key.
 *
 * Rate-limit detection: ClanWorld.heartbeat() reverts when called before
 * `nextHeartbeatAtTs`. We don't have a typed custom error in the ABI, so on
 * any revert we re-read `getWorldState().nextHeartbeatAtTs` and, if it is
 * still in the future, throw `HeartbeatRateLimitedError(nextAllowedAt)`.
 * Other reverts surface as the original error.
 */
export class RunnerCastHeartbeat implements IHeartbeatCaller {
  private readonly publicClient: PublicClient;
  private readonly walletClient: WalletClient;
  private readonly account: Account;
  private readonly contractAddress: `0x${string}`;

  constructor(cfg: RunnerHeartbeatConfig) {
    const pk = normalizePk(cfg.privateKey);
    this.account = privateKeyToAccount(pk);
    const transport = cfg.rpcUrl ? http(cfg.rpcUrl) : http();
    this.publicClient = createPublicClient({ chain: baseSepolia, transport });
    this.walletClient = createWalletClient({
      account: this.account,
      chain: baseSepolia,
      transport,
    });
    this.contractAddress = cfg.contractAddress;
  }

  async callHeartbeat(): Promise<{ txHash: string }> {
    try {
      const hash = await this.walletClient.writeContract({
        account: this.account,
        chain: baseSepolia,
        address: this.contractAddress,
        abi: CLAN_WORLD_ABI,
        functionName: 'heartbeat',
        args: [],
      });
      // Wait for confirmation per the seam contract ("not fire-and-forget").
      const receipt = await this.publicClient.waitForTransactionReceipt({ hash });
      if (receipt.status !== 'success') {
        // Mined-but-reverted. Most common cause is the rate-limit window
        // hadn't elapsed yet (when simulation succeeded but execution didn't).
        // Re-read state to upgrade to HeartbeatRateLimitedError when applicable.
        const next = await this.readNextHeartbeatAt().catch(() => undefined);
        if (next !== undefined && next > Math.floor(Date.now() / 1000)) {
          throw new HeartbeatRateLimitedError(next);
        }
        throw new Error(`heartbeat tx ${hash} reverted on-chain`);
      }
      return { txHash: hash };
    } catch (err) {
      // Already a rate-limit error — rethrow immediately; no second RPC read.
      if (err instanceof HeartbeatRateLimitedError) throw err;
      // Attempt to upgrade only simulation-level contract reverts to
      // HeartbeatRateLimitedError; pre-flight/RPC errors must surface unchanged.
      if (!(err instanceof ContractFunctionRevertedError)) throw err;
      const next = await this.readNextHeartbeatAt().catch(() => undefined);
      if (next !== undefined && next > Math.floor(Date.now() / 1000)) {
        throw new HeartbeatRateLimitedError(next);
      }
      throw err;
    }
  }

  async isHeartbeatDue(): Promise<boolean> {
    const next = await this.readNextHeartbeatAt();
    return next <= Math.floor(Date.now() / 1000);
  }

  private async readNextHeartbeatAt(): Promise<number> {
    const state = await this.publicClient.readContract({
      address: this.contractAddress,
      abi: CLAN_WORLD_ABI,
      functionName: 'getWorldState',
      args: [],
    });
    // viem decodes the named tuple into an object with the same field names.
    return Number((state as { nextHeartbeatAtTs: bigint }).nextHeartbeatAtTs);
  }
}

function normalizePk(pk: string): `0x${string}` {
  const trimmed = pk.trim();
  const withPrefix = trimmed.startsWith('0x') ? trimmed : `0x${trimmed}`;
  if (!/^0x[0-9a-fA-F]{64}$/.test(withPrefix)) {
    throw new Error(
      'RUNNER_PRIVATE_KEY is not a valid 64-hex-char private key (0x-prefixed optional)',
    );
  }
  return withPrefix as `0x${string}`;
}
