// IKeeper — abstraction over the heartbeat driver. Three impls per the v4.5
// addendum §3:
//   - FoundryLoopKeeper   — Submission 1 (World, 20s) and all local dev
//   - KeeperHubKeeper     — Submission 2 live demo (Base Sepolia, 60s cron)
//   - ConvexCronKeeper    — disaster fallback only (HEARTBEAT_CALLER_ENABLED=true)
import { readEnv } from './_env';

export interface IKeeper {
  start(): Promise<void>;
  stop(): Promise<void>;
}

class FoundryLoopKeeper implements IKeeper {
  async start(): Promise<void> {
    throw new Error('FoundryLoopKeeper: not implemented (Wave 1+)');
  }
  async stop(): Promise<void> {
    // no-op stub
  }
}

class KeeperHubKeeper implements IKeeper {
  async start(): Promise<void> {
    throw new Error('KeeperHubKeeper: not implemented (Submission 2)');
  }
  async stop(): Promise<void> {
    // no-op stub
  }
}

class ConvexCronKeeper implements IKeeper {
  async start(): Promise<void> {
    throw new Error('ConvexCronKeeper: not implemented (fallback only)');
  }
  async stop(): Promise<void> {
    // no-op stub
  }
}

export function createKeeper(): IKeeper {
  const mode = readEnv('KEEPER_MODE') ?? 'foundry-loop';
  switch (mode) {
    case 'foundry-loop':
      return new FoundryLoopKeeper();
    case 'keeperhub':
      return new KeeperHubKeeper();
    case 'convex':
      return new ConvexCronKeeper();
    default:
      throw new Error(`unknown KEEPER_MODE=${mode}`);
  }
}
