import { goldDeployment } from '../generated/goldDeployment';

export function SetupChecklist() {
  const checks = [
    ['Solana token mint set', Boolean(goldDeployment.solana.token)],
    ['Solana NTT manager set', Boolean(goldDeployment.solana.manager)],
    ['Solana transceiver set', Boolean(goldDeployment.solana.transceiver)],
    ['Base token set', Boolean(goldDeployment.base.token)],
    ['Base NTT manager set', Boolean(goldDeployment.base.manager)],
    ['Base transceiver set', Boolean(goldDeployment.base.transceiver)],
    ['Solana RPC set', Boolean(goldDeployment.solana.rpcUrl)],
    ['Base RPC set', Boolean(goldDeployment.base.rpcUrl)]
  ];

  return (
    <section className="card">
      <h2>Setup checklist</h2>
      <div className="check-list">
        {checks.map(([label, ok]) => (
          <div className="check-row" key={String(label)}>
            <span className={ok ? 'check-ok' : 'check-missing'}>{ok ? 'Ready' : 'Missing'}</span>
            <span>{label}</span>
          </div>
        ))}
      </div>
    </section>
  );
}
