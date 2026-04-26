# Prize Strategy

Two stacked submissions. Different audiences, different judging criteria.

## Submission 1 — World mini app hackathon

**Deadline:** 2026-04-26 14:00 ET (~6 hours from Wave 0).
**Chain:** World Chain Sepolia.
**Target:** ship a recordable demo of ClanWorld running inside the World App, end-to-end. The 8 demo moments from `docs/planning/V1/01 Blockchain Game Spec/clanworld_v1_implementation_profile.md` §8.

### Strategy: thin wrapper

The World mini app integration is **a thin wrapper, not the core narrative**. The judges evaluating this hackathon want to see World mini apps that work — they're not deeply scoring how creative the World ID flow is. Our differentiator is the autonomous-LLM-strategy-game part, not the World plumbing.

**Therefore:**
- Add `@worldcoin/minikit-js` and `@worldcoin/idkit` to `apps/web/package.json` (done in Wave 0).
- Mention "ClanWorld is a World mini app — wrapped with `@worldcoin/minikit-js`, with World ID humanity verification at clan mint" in `README.md` (done in Wave 0).
- **Do not** spend Wave 0–4 hours on real MiniKit integration code. The package presence + README sentence is enough optical signal for Submission 1.
- **Do** punch through the actual World hackathon submission requirements during Wave 4 polish — answer the §5.1 questions in `architecture-decisions.md` and add the bare minimum integration if any specific gate is required.

### Cut priorities for Submission 1

If we're behind at the H3 gate, in this order:
1. **Cut** real Elders → mock Elders driving canned moves.
2. **Cut** Pixi sprites → SVG region polygons + plain HTML chrome.
3. **Cut** live demo recording → screen-recorded demo from local machine.

### Never cut

- Chain has `IClanWorld` deployed on World Chain Sepolia.
- At least one real `heartbeat()` tx fires on testnet.
- The 8 demo moments are visible (even if some are scripted).
- The frontend is reachable via the World App as a mini app.

---

## Submission 2 — OpenAgents Track 2

**Deadline:** 2026-05-05.
**Chain:** Base Sepolia.
**Target:** the iNFT transfer demo punchline. A clan iNFT is minted (ERC-7857), the agent reasons, the iNFT is transferred to a new owner with full key handover, the new owner's reasoning continues with the same clan memory.

### Strategy: punchline-first

Track 2 judges evaluate "what new agent capabilities does this demo show?". Our punchline:

> ClanWorld clans are **iNFTs** — autonomous agents whose memory and authorization travel with the NFT. Watch this clan get minted by Alice, fight for region control, then transfer to Bob mid-game. Bob inherits the agent's full memory and continues the strategy seamlessly.

This is the demo. Everything else (8 demo moments, regions, missions) is the gameplay backdrop.

### Stack additions vs Submission 1

| Component | Submission 1 | Submission 2 |
|---|---|---|
| Chain | World Chain Sepolia | Base Sepolia |
| Heartbeat | Foundry shell loop | KeeperHub workflow |
| Tick | 20s | 60s |
| Storage | (none) | 0G Storage KV (`ClanMemory` library) |
| Identity | (none) | ERC-7857 iNFT (`ClanIdentity` library) |
| Whispers | onchain only | AXL message transport |
| Sealed inference | (none) | 0G compute (optional, TBD) |

### Cut priorities for Submission 2

If we're behind in the final 24 hours:
1. **Cut** sealed inference (0G compute) — keep Anthropic for Elder reasoning, lose 1 bullet.
2. **Cut** AXL whispers — fall back to Convex-relayed in-game whispers.
3. **Cut** the second clan in the transfer demo — show transfer via testnet explorer link instead of live mid-game.

### Never cut

- Single live iNFT mint + transfer + key-authorization handover demonstrating continuity of clan memory.

---

## Cross-submission consistency

- **Same codebase**, parameterized by chain. Don't fork.
- **Same `IClanWorld` ABI.** S1 deployment of the contract is byte-for-byte identical to S2.
- **Same `IKeeper` interface**, two different impls (`FoundryLoopKeeper` for S1, `KeeperHubKeeper` for S2).
- **Same Convex backend code,** different `CONVEX_URL` per realm.

This is the entire point of the adapter pattern in `packages/shared/src/adapters/`.
