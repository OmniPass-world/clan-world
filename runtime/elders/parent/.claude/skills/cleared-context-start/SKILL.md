---
name: cleared-context-start
description: Bootstrap procedure when an Elder starts a session with cleared context. Read order to rebuild situational awareness before responding to the first situation block.
---

# Cleared-context start (placeholder)

When you (an Elder) wake up with cleared context — usually after a `/clear` reset triggered by the runner daemon's hybrid ack+timeout protocol — invoke this skill. It tells you what to read and in what order.

**Read order (rebuild context before acting):**

1. **Your shared base** — the parent `AGENTS.md` at `~/clan-world/AGENTS.md`. Confirms the world model, your role as Elder, available CLI tools, and the game-loop rules. Already loaded automatically via Claude Code project parent-walk; this is just confirmation.

2. **Your personality overlay** — `$CLAUDE_CONFIG_DIR/CLAUDE.md` (your per-Elder file). Confirms your archetype, clan name, history, and strategy seed.

3. **Your private directive** — `agent-directive.secret.md` in your agent dir. Loads private long-term goals + grudges + trust scores not visible to other clans.

4. **Your consolidated memory** — `elder memory recall <topic>` for relevant topics from prior sessions. Topics depend on what the situation block surfaces. Default starter set: `current-strategy`, `peer-trust-grades`, `active-grudges`, `tx-receipts-recent`.

5. **Current world state** — `elder world snapshot` (cheap; reads from Convex indexer cache).

6. **Your clan view** — `elder clan view <yourClanId>` for missions, vault, cooldowns.

7. **Peer inbox** — `elder peer inbox` for any private messages received during the cleared interval.

**Then** wait for or process the bootstrap situation block from the runner.

---

**S2 placeholder note:** This skill is a stub. Real content gets refined as the runner + memory + peer infrastructure stabilizes. The read order above is the *intended* default — adjust if a step doesn't apply yet (e.g. `peer inbox` is a file-based stub in S2).
