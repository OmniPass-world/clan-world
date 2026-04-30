import { goldDeployment } from '../generated/goldDeployment';
import { evmExplorerAddress, shortenAddress, solanaExplorerAddress } from '../lib/format';

interface LinkRowProps {
  label: string;
  href?: string;
  value: string;
}

function LinkRow({ label, href, value }: LinkRowProps) {
  return (
    <div className="link-row">
      <span>{label}</span>
      {href && value ? (
        <a href={href} target="_blank" rel="noreferrer">{shortenAddress(value)}</a>
      ) : (
        <strong>{shortenAddress(value)}</strong>
      )}
    </div>
  );
}

export function ExplorerLinks() {
  const solanaCluster = goldDeployment.solana.explorerCluster;
  const baseExplorer = goldDeployment.base.explorerUrl || 'https://sepolia.basescan.org';
  return (
    <section className="card">
      <h2>Addresses</h2>
      <h3>Solana</h3>
      <LinkRow label="GOLD mint" value={goldDeployment.solana.token} href={goldDeployment.solana.token ? solanaExplorerAddress(goldDeployment.solana.token, solanaCluster) : undefined} />
      <LinkRow label="NTT manager" value={goldDeployment.solana.manager} href={goldDeployment.solana.manager ? solanaExplorerAddress(goldDeployment.solana.manager, solanaCluster) : undefined} />
      <LinkRow label="Transceiver" value={goldDeployment.solana.transceiver} href={goldDeployment.solana.transceiver ? solanaExplorerAddress(goldDeployment.solana.transceiver, solanaCluster) : undefined} />
      <h3>Base</h3>
      <LinkRow label="GOLD ERC-20" value={goldDeployment.base.token} href={goldDeployment.base.token ? evmExplorerAddress(baseExplorer, goldDeployment.base.token) : undefined} />
      <LinkRow label="NTT manager" value={goldDeployment.base.manager} href={goldDeployment.base.manager ? evmExplorerAddress(baseExplorer, goldDeployment.base.manager) : undefined} />
      <LinkRow label="Transceiver" value={goldDeployment.base.transceiver} href={goldDeployment.base.transceiver ? evmExplorerAddress(baseExplorer, goldDeployment.base.transceiver) : undefined} />
    </section>
  );
}
