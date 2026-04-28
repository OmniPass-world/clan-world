/**
 * IElderPeerInbox — private Elder-to-Elder diplomacy transport.
 *
 * S2 stub: file-based jsonl at ~/.world/clanworld-runner/state/peer-inbox/elder-{recipientClanId}.jsonl
 * Phase 8: Gensyn AXL private messaging transport
 *
 * Contract:
 * - Messages are ordered (FIFO) within a sender/recipient pair per tick.
 * - Peer messages are agent-private: not mirrored to Convex or the UI in S2.
 *   (Phase 8: Convex getPeerMessagesFor() switches from file to AXL transport.)
 * - send() writes to the RECIPIENT's inbox (indexed by recipient clan ID), not the sender's.
 * - inbox() reads the caller Elder's own inbox (indexed by the Elder's own clan ID).
 * - Implementations must be idempotent: the runner may re-deliver a whisper on retry;
 *   implementations that guarantee exactly-once must deduplicate by (fromClanId, tick, msgId).
 */
export interface IElderPeerInbox {
  /**
   * Send a whisper to another clan's Elder.
   *
   * @param toClanId - recipient clan ID (determines which inbox file / AXL channel to write)
   * @param message  - free-text message content (≤ 500 chars recommended for AXL compat)
   * @param tick     - current game tick (used for ordering and deduplication)
   */
  send(toClanId: string, message: string, tick: number): Promise<void>;

  /**
   * Read all unread messages in this Elder's own inbox.
   *
   * Contract:
   * - Returns messages in arrival order.
   * - Does NOT consume/delete messages — same messages returned on next call.
   *   (Stateful consumption is the Elder's responsibility via memory store.)
   * - Must not throw if inbox is empty or does not yet exist.
   */
  inbox(): Promise<PeerMessage[]>;
}

export interface PeerMessage {
  fromClanId: string;
  toClanId: string;
  message: string;
  tick: number;
  /** ISO 8601 timestamp of when the message was sent. */
  sentAt: string;
}
