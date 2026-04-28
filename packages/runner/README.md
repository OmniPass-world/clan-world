# @clan-world/runner

ClanWorld runner daemon — drives 4 Elder Claude Code sessions through the
per-tick reasoning loop.

## What it does

```
loop:
  chainTick = pollChainTick(convex)
  if chainTick > lastProcessedTick:
    parallel for elder in 1..4:
      block = composeSituationBlock(elder, chainTick, ...)
      tmux send-keys -t elder-N -l "$block" + Enter
    settle window (~90s) — Elders read, reason, submit orders
    heartbeat() on-chain (rate-limit aware)
    lastProcessedTick = chainTick
  sleep pollInterval
```

The runner is the **only** writer of situation blocks into Elder sessions. It
satisfies four seam interfaces from `@clan-world/agents/seams`:

| Seam                  | Impl                       | Notes                                              |
| --------------------- | -------------------------- | -------------------------------------------------- |
| `IRunnerInbox`        | `TmuxRunnerInbox`          | `tmux send-keys -l` + paste block + Enter         |
| `IElderMemoryStore`   | `FileMemoryStore`          | `~/.world/clanworld-runner/state/elder-N-memory.json` |
| `IElderPeerInbox`     | `FilePeerInbox`            | JSONL per recipient clan                          |
| `IHeartbeatCaller`    | `RunnerCastHeartbeat`      | viem `writeContract`, dedicated runner wallet     |

## Run it

```bash
# 1. Provision a fresh runner wallet (NEVER reuse an Elder key) and fund it
#    with World Chain Sepolia ETH.
export RUNNER_PRIVATE_KEY=0x...
export CLAN_WORLD_CONTRACT_ADDRESS=0xC012275376b867944cd874FB2d600d6dA3B4A56e
export CONVEX_URL=https://...convex.cloud   # optional; runner idles without it

# 2. Make sure 4 tmux sessions exist with Elder Claude Code already attached:
#    elder-1, elder-2, elder-3, elder-4

# 3. Start the daemon:
pnpm --filter @clan-world/runner start
```

## Env vars

See [`.env.example`](./.env.example). All vars are read from `process.env`
at startup — the daemon does **not** auto-load any `.env` file.

## State directory

Default: `~/.world/clanworld-runner/state/`. Layout:

```
elder-1-memory.json          ← FileMemoryStore
elder-2-memory.json
elder-3-memory.json
elder-4-memory.json

elder-1-last-tick.txt        ← TmuxRunnerInbox idempotency marker
elder-2-last-tick.txt
…

elder-1-ack.flag             ← Set by `elder ack-clear` from Elder side
…

peer-inbox/
  elder-1.jsonl              ← FilePeerInbox; one file per recipient clan
  elder-2.jsonl
  …
```

## Stub mode

- If `CONVEX_URL` is unset, `createConvexClient()` hands back a stub returning
  `{ tick: 0, ... }`. The tick loop interprets this as "no real chain state"
  and idles (logs a warning at boot).
- If `RUNNER_PRIVATE_KEY` is missing, the daemon refuses to start.

## systemd

Template unit file: [`clanworld-runner.service`](./clanworld-runner.service).
Install with:

```bash
mkdir -p ~/.config/systemd/user
cp packages/runner/clanworld-runner.service ~/.config/systemd/user/
mkdir -p ~/.config/clanworld-runner
cp packages/runner/.env.example ~/.config/clanworld-runner/runner.env
chmod 600 ~/.config/clanworld-runner/runner.env
# edit runner.env, then:
systemctl --user daemon-reload
systemctl --user enable --now clanworld-runner.service
```

## Known TODOs

- `pollChainTick` reads the full snapshot — switch to a dedicated
  `getCurrentTick` Convex query once it exists.
- Heartbeat rate-limit detection re-reads `getWorldState()` after a revert.
  When a typed `HeartbeatTooSoon` custom error lands in the contract ABI,
  upgrade `RunnerCastHeartbeat.callHeartbeat` to decode it directly.
