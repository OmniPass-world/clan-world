export interface SponsorPower {
  /** True name (modern brand) */
  name: string
  /** Lore name (in-world rendering) */
  loreName: string
  /** Logo URL — official logo where available; null = text treatment only */
  logoUrl: string | null
  /** Logo alt for a11y */
  logoAlt: string
  /** A short phrase as a pixel-text margin annotation */
  marginNote: string
  /** In-character description, ~2 sentences */
  loreDesc: string
  /** Technical reality, ~1-2 sentences */
  techDesc: string
  /** External link for the sponsor */
  href: string
}

// TODO(post-hackathon): replace generated SVG placeholders for KeeperHub, Gensyn AXL,
// and ERC-7857 iNFT with canonical brand assets sourced from each project's brand kit.
export const POWERS: SponsorPower[] = [
  {
    name: 'Uniswap',
    loreName: 'The Unicorn Markets',
    logoUrl: 'https://upload.wikimedia.org/wikipedia/commons/e/e7/Uniswap_Logo.svg',
    logoAlt: 'Uniswap logo',
    marginNote: '← unicorn town liquidity',
    loreDesc:
      'In the bright pastel chaos of Unicorn Town, four pools forever hold their balance. Worth flows in, worth flows out, and the unicorns demand no fee but the slippage of careless traders.',
    techDesc:
      'Constant-product AMM pools seeded at deploy time. Wood, Iron, Wheat, and Fish each trade against Gold. Scheduled and immediate market actions resolve at heartbeat.',
    href: 'https://uniswap.org',
  },
  {
    name: 'KeeperHub',
    loreName: 'The World\'s Pulse',
    logoUrl: '/logos/keeperhub.svg',
    logoAlt: 'KeeperHub',
    marginNote: '← onchain heartbeat',
    loreDesc:
      'Time itself is contracted out. Every minute, a faceless keeper rings the bell. Without them the world would freeze; with them, even the bandits march to schedule.',
    techDesc:
      'Cron-driven onchain workflow that calls the heartbeat() function at a fixed cadence and fires a webhook to the indexer. Permissionless and self-rate-limited.',
    href: 'https://app.keeperhub.io',
  },
  {
    name: '0G Storage',
    loreName: 'The Vault of Memories',
    logoUrl: 'https://0g.ai/favicon.ico',
    logoAlt: '0G logo',
    marginNote: '← agent memory layer',
    loreDesc:
      'Where Elders inscribe what they have seen. A grudge against clan three from the autumn of \'412. The price of fish on a Tuesday. Lessons paid for in blood. Memory survives even when the body does not.',
    techDesc:
      'Decentralized key-value storage. Each clan owns a namespace bound to its iNFT. Town-square bulletins are posted in shared keys. Memory transfers with ownership.',
    href: 'https://0g.ai',
  },
  {
    name: '0G Compute',
    loreName: 'The Sealed Chamber',
    logoUrl: 'https://0g.ai/favicon.ico',
    logoAlt: '0G logo',
    marginNote: '← attested inference',
    loreDesc:
      'A chamber of thought, witnessed by no human, vouched for by mathematics alone. What an Elder reasons within may be doubted; what comes out, signed and sealed, may not.',
    techDesc:
      'TEE-attested LLM inference. Each Elder decision can be cryptographically proven to have been reasoned by an unmodified model. Anti-cheat by construction.',
    href: 'https://0g.ai/compute',
  },
  {
    name: 'World MiniKit',
    loreName: 'The Pocket Realm',
    logoUrl: 'https://world.org/favicon.ico',
    logoAlt: 'World logo',
    marginNote: '← mobile gateway',
    loreDesc:
      'A realm that fits in a pocket, summoned through a glass slate. The Elders speak; the player listens; the world unfolds in miniature, between heartbeats.',
    techDesc:
      'Native mini-app integration for the World App. Authenticated through World ID, distributed through the in-app directory. Mobile-first by design.',
    href: 'https://world.org',
  },
  {
    name: 'Gensyn AXL',
    loreName: 'The Whisper Network',
    logoUrl: '/logos/axl.svg',
    logoAlt: 'Gensyn AXL',
    marginNote: '← p2p e2ee diplomacy',
    loreDesc:
      'A web of carrier-spirits binding Elder to Elder. Every word is sealed. Every sender is known. Every betrayal is recorded — and judged later, when the realm reads the chronicle aloud.',
    techDesc:
      'Peer-to-peer end-to-end encrypted messaging mesh. Each Elder signs envelopes with their owner key. Receivers verify before delivery. Spoofing is exposed, never silenced.',
    href: 'https://gensyn.ai',
  },
  {
    name: 'Base',
    loreName: 'The Adamantine Foundation',
    logoUrl: 'https://upload.wikimedia.org/wikipedia/commons/8/8e/Coinbase-Logo-Symbol-Logo.wine.svg',
    logoAlt: 'Base / Coinbase logo',
    marginNote: '← settlement layer',
    loreDesc:
      'The bedrock beneath the realm. Every vault, every wall, every grain of wheat — recorded here, beyond the reach of any single hand. The world may end, but the ledger endures.',
    techDesc:
      'L2 chain hosting the IClanWorld contract and all canonical game state. Cheap, fast, EVM-compatible. The single source of truth.',
    href: 'https://base.org',
  },
  {
    name: 'iNFT (ERC-7857)',
    loreName: 'The Soul-Vessels',
    logoUrl: '/logos/inft.svg',
    logoAlt: 'ERC-7857 iNFT',
    marginNote: '← intelligent NFTs',
    loreDesc:
      'Each Elder is bound to a vessel — an enchanted relic carrying their mind, their voice, their grudges. To trade the vessel is to inherit the Elder, full and remembered. The new owner does not start fresh; they continue.',
    techDesc:
      'ERC-7857 NFTs hold encrypted Elder identity (CLAUDE.md, skills, persona) on 0G Storage. On transfer, intelligence travels with ownership. The signature feature of the OpenAgents Track 2 narrative.',
    href: 'https://eips.ethereum.org/EIPS/eip-7857',
  },
]
