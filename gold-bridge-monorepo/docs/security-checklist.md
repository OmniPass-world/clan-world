# Security checklist

Before mainnet liquidity:

- Solana NTT is locking mode.
- Base NTT is burning mode.
- Base token minter is Base NTT manager.
- Token owner is a timelock.
- ProxyAdmin owner is the same timelock.
- Timelock proposer is a multisig.
- Timelock delay is long enough for public review.
- NTT manager owners are multisigs.
- Pauser roles are assigned intentionally.
- Rate limits are conservative.
- Recovery allowlist contains only intended ClanWorld, treasury, or pool contracts.
- Recovery plan and permanent-disable plan are documented.
- All deployer keys are rotated out or reduced in authority.
- Frontend config matches on-chain deployment.
- Small transfers work both directions.
- Monitoring works.
- External review completed.
