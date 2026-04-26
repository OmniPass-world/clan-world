# Sponsor Tech — quick reference

Notes on the third-party technologies we depend on. Mostly placeholders for Wave 2 research output. Update as PoCs land.

## World mini app SDK (Submission 1)

- **Package:** `@worldcoin/minikit-js`
- **Purpose:** wrap `apps/web` so it loads inside the World App with native APIs (auth, payments, share).
- **Wave 0 status:** dep installed, no integration code.
- **Open questions** (per addendum §5.1):
  - Required surface area: auth? payments? share? all three?
  - Does the submission gate on a specific UX flow?
  - Is distribution via World App directory or direct URL?
- **Action:** PM resolves these in Wave 2.

## World ID (Submission 1, optional)

- **Package:** `@worldcoin/idkit`
- **Purpose:** humanity verification at clan mint.
- **Wave 0 status:** dep installed.
- **Note:** if S1 doesn't require World ID, the dep stays as a future-S2 nice-to-have.

## 0G Storage KV (Submission 2)

- **Library:** `ClanMemory` (TBD, in `packages/contracts/src/`).
- **Purpose:** persist clan agent memory off-chain but verifiably; survives iNFT transfers.
- **Reference:** `docs/planning/V1/05 0G/clanworld_clan_memory_spec.md`.
- **Open questions:** key authorization model under iNFT transfer; performance ceiling on per-tick reads.
- **Action:** Wave 2 PoC validates "can we read N keys from 0G Storage in under TICK_DURATION_MS / 4?"

## ERC-7857 iNFT (Submission 2)

- **Library:** `ClanIdentity` (TBD, in `packages/contracts/src/`).
- **Purpose:** clans are iNFTs whose authorization key handovers to the new owner on transfer.
- **Reference:** `docs/planning/V1/05 0G/clanworld_clan_identity_spec.md` and `clanworld_inft_deployment_notes.md`.
- **Open questions:** does the reference impl support our key handover flow without modification?
- **Action:** Wave 2 PoC mints a test iNFT, transfers it, verifies authorization continuity.

## Gensyn AXL (Submission 2)

- **Purpose:** off-chain agent-to-agent whisper transport.
- **Reference:** `docs/planning/V1/04 AXL integration spec.pdf`.
- **Open questions:** rate limits, identity binding to clan addresses.
- **Action:** Wave 2 PoC sends a whisper between two test agents.

## KeeperHub (Submission 2)

- **Purpose:** decentralized cron driving the heartbeat() call on Base Sepolia.
- **Reference:** `docs/planning/V1/03 KeeperHub integration spec.pdf` + `docs/planning/V1/01 Blockchain Game Spec/clanworld v4 5 keeper integration spec.pdf`.
- **Wave 0 status:** abstracted behind `IKeeper`. `KeeperHubKeeper` impl stubbed.
- **Open questions:** workflow definition syntax for HTTP webhook fan-out.
- **Action:** Wave 5 (Submission 2 build) ships the workflow.

## 0G Compute (Submission 2, optional)

- **Purpose:** sealed inference for Elder reasoning — proves no-tampering on agent decisions.
- **Wave 0 status:** abstracted behind `ILLMClient` (`ZeroGClient` impl stubbed).
- **Open questions:** model availability, throughput, latency vs Anthropic baseline.
- **Action:** Wave 2 PoC measures latency of one Elder turn through 0G compute.

## Cloudflare / static hosting

- **Wave 0 status:** none.
- **Plan:** `apps/web` builds to static; deploy to Vercel or Cloudflare Pages. URL goes into the World App mini app registration.
