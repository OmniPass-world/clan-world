import { useEffect, useMemo, useState } from 'react';
import { BridgePanel } from './BridgePanel';
import {
  fetchCockpitActions,
  fetchCockpitState,
  previewCockpitAction,
  runCockpitAction
} from '../lib/cockpitApi';
import { evmExplorerAddress, evmExplorerTx, shortenAddress, solanaExplorerAddress, solanaExplorerTx } from '../lib/format';
import type { CockpitAction, CockpitActionPreview, CockpitActionResult, CockpitState } from '../types';

type Tab = 'overview' | 'addresses' | 'authority' | 'deploy' | 'upgrade' | 'recovery' | 'bridge';

const tabs: Array<{ id: Tab; label: string }> = [
  { id: 'overview', label: 'Overview' },
  { id: 'addresses', label: 'Addresses' },
  { id: 'authority', label: 'Authority' },
  { id: 'deploy', label: 'Deploy' },
  { id: 'upgrade', label: 'Upgrade' },
  { id: 'recovery', label: 'Recovery' },
  { id: 'bridge', label: 'Bridge' }
];

export function CockpitDashboard() {
  const [tab, setTab] = useState<Tab>('overview');
  const [state, setState] = useState<CockpitState | null>(null);
  const [actions, setActions] = useState<CockpitAction[]>([]);
  const [evmWallet, setEvmWallet] = useState('');
  const [solanaWallet, setSolanaWallet] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  async function refresh() {
    setLoading(true);
    setError('');
    try {
      const [nextState, nextActions] = await Promise.all([fetchCockpitState(), fetchCockpitActions()]);
      setState(nextState);
      setActions(nextActions);
    } catch (err) {
      setError(String((err as Error).message || err));
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    void refresh();
  }, []);

  return (
    <main className="app-shell cockpit-shell">
      <header className="cockpit-header">
        <div>
          <p className="eyebrow">GOLD bridge operator</p>
          <h1>Deployment Cockpit</h1>
          <p>Monitor, deploy, configure, upgrade, and recover the Solana-to-Base GOLD bridge from one local control surface.</p>
        </div>
        <div className="header-actions">
          <EnvironmentPill state={state} />
          <button onClick={() => void connectEvmWallet(setEvmWallet)}>{evmWallet ? shortenAddress(evmWallet) : 'Connect EVM'}</button>
          <button onClick={() => void connectSolanaWallet(setSolanaWallet)}>{solanaWallet ? shortenAddress(solanaWallet) : 'Connect Solana'}</button>
          <button onClick={() => void refresh()} disabled={loading}>{loading ? 'Refreshing' : 'Refresh'}</button>
        </div>
      </header>

      {error && <section className="banner warning">Cockpit API unavailable: {error}. Start it with <code>pnpm cockpit:api</code>.</section>}

      <nav className="tab-bar" aria-label="Cockpit sections">
        {tabs.map((item) => (
          <button key={item.id} className={tab === item.id ? 'active' : ''} onClick={() => setTab(item.id)}>
            {item.label}
          </button>
        ))}
      </nav>

      {state && (
        <>
          {tab === 'overview' && <Overview state={state} evmWallet={evmWallet} solanaWallet={solanaWallet} />}
          {tab === 'addresses' && <Addresses state={state} />}
          {tab === 'authority' && <Authority state={state} />}
          {tab === 'deploy' && <Workflow state={state} actions={actions.filter((item) => ['setup', 'deploy', 'config', 'verify', 'proof', 'artifact'].includes(item.group))} />}
          {tab === 'upgrade' && <Upgrade state={state} actions={actions.filter((item) => item.group === 'upgrade' || item.id === 'proxy-info')} />}
          {tab === 'recovery' && <Recovery state={state} actions={actions.filter((item) => item.group === 'recovery')} />}
          {tab === 'bridge' && <BridgePanel />}
        </>
      )}
    </main>
  );
}

async function connectEvmWallet(setter: (value: string) => void) {
  const provider = (window as unknown as { ethereum?: { request: (args: { method: string; params?: unknown[] }) => Promise<string[]> } }).ethereum;
  if (!provider) {
    window.alert('No EVM wallet provider found in this browser.');
    return;
  }
  try {
    const accounts = await provider.request({ method: 'eth_requestAccounts' });
    setter(accounts[0] || '');
  } catch (err) {
    window.alert(String((err as Error).message || err));
  }
}

async function connectSolanaWallet(setter: (value: string) => void) {
  const provider = (window as unknown as { solana?: { connect: () => Promise<{ publicKey?: { toString: () => string } }> } }).solana;
  if (!provider) {
    window.alert('No Solana wallet provider found in this browser.');
    return;
  }
  try {
    const result = await provider.connect();
    setter(result.publicKey?.toString() || '');
  } catch (err) {
    window.alert(String((err as Error).message || err));
  }
}

function EnvironmentPill({ state }: { state: CockpitState | null }) {
  if (!state) return <div className="network-pill">API offline</div>;
  return (
    <div className={state.environment.isMainnet ? 'network-pill danger-pill' : 'network-pill'}>
      {state.environment.wormholeNetwork} · {state.addresses.solana.chain} / {state.addresses.base.chain}
    </div>
  );
}

function Overview({ state, evmWallet, solanaWallet }: { state: CockpitState; evmWallet: string; solanaWallet: string }) {
  const failed = state.checks.filter((item) => !item.ok);
  return (
    <div className="cockpit-grid">
      <section className="panel wide">
        <div className="panel-title-row">
          <h2>Readiness</h2>
          <StatusPill ok={failed.length === 0} label={failed.length === 0 ? 'Ready' : `${failed.length} warnings`} />
        </div>
        <div className="check-grid">
          {state.checks.map((item) => (
            <div className="check-card" key={item.id}>
              <StatusPill ok={item.ok} label={item.ok ? 'OK' : 'Check'} />
              <strong>{item.label}</strong>
              {item.detail && <span>{item.detail}</span>}
            </div>
          ))}
        </div>
      </section>

      <Metric title="Solana GOLD supply" value={state.token.solanaSupply || 'not loaded'} />
      <Metric title="Base GOLD supply" value={state.token.baseSupply || 'not loaded'} />
      <Metric title="Solana deployer SOL" value={state.balances.solanaDeployerSol || 'not loaded'} />
      <Metric title="Base deployer ETH" value={state.balances.baseDeployerEth || 'not loaded'} />
      <Metric title="Solana deployer GOLD" value={state.balances.solanaDeployerGold || 'not loaded'} />
      <Metric title="Base deployer GOLD" value={state.balances.baseDeployerGold || 'not loaded'} />

      <section className="panel wide">
        <h2>Connected wallets</h2>
        <Rows rows={[
          ['EVM wallet', evmWallet || 'not connected'],
          ['Solana wallet', solanaWallet || 'not connected'],
          ['WalletConnect project id', state.environment.walletConnectProjectIdConfigured ? 'configured' : 'not configured'],
          ['Mainnet key policy', state.environment.isMainnet ? 'wallet or timelock only' : 'testnet local scripts allowed']
        ]} />
      </section>

      <section className="panel wide">
        <h2>Latest proof txs</h2>
        <TransactionRows state={state} />
      </section>
    </div>
  );
}

function Addresses({ state }: { state: CockpitState }) {
  const baseExplorer = state.addresses.base.explorerUrl;
  return (
    <div className="two-column">
      <section className="panel">
        <h2>Solana</h2>
        <Rows rows={[
          ['Deployer', state.addresses.solana.deployer, solanaExplorerAddress(state.addresses.solana.deployer, state.addresses.solana.explorerCluster)],
          ['GOLD mint', state.addresses.solana.token, solanaExplorerAddress(state.addresses.solana.token, state.addresses.solana.explorerCluster)],
          ['NTT manager', state.addresses.solana.manager, solanaExplorerAddress(state.addresses.solana.manager, state.addresses.solana.explorerCluster)],
          ['Transceiver', state.addresses.solana.transceiver, solanaExplorerAddress(state.addresses.solana.transceiver, state.addresses.solana.explorerCluster)],
          ['Owner', state.addresses.solana.owner, state.addresses.solana.owner ? solanaExplorerAddress(state.addresses.solana.owner, state.addresses.solana.explorerCluster) : '']
        ]} />
      </section>
      <section className="panel">
        <h2>Base</h2>
        <Rows rows={[
          ['Deployer', state.addresses.base.deployer, evmExplorerAddress(baseExplorer, state.addresses.base.deployer)],
          ['GOLD proxy', state.addresses.base.token, evmExplorerAddress(baseExplorer, state.addresses.base.token)],
          ['Implementation', state.addresses.base.implementation || state.proxy.implementation, evmExplorerAddress(baseExplorer, state.addresses.base.implementation || state.proxy.implementation)],
          ['ProxyAdmin', state.addresses.base.proxyAdmin || state.proxy.admin, evmExplorerAddress(baseExplorer, state.addresses.base.proxyAdmin || state.proxy.admin)],
          ['Timelock', state.addresses.base.timelock, evmExplorerAddress(baseExplorer, state.addresses.base.timelock)],
          ['NTT manager', state.addresses.base.manager, evmExplorerAddress(baseExplorer, state.addresses.base.manager)],
          ['Transceiver', state.addresses.base.transceiver, evmExplorerAddress(baseExplorer, state.addresses.base.transceiver)]
        ]} />
      </section>
    </div>
  );
}

function Authority({ state }: { state: CockpitState }) {
  return (
    <div className="two-column">
      <section className="panel">
        <h2>Base token and proxy</h2>
        <Rows rows={[
          ['Token owner', state.authority.base.tokenOwner],
          ['Token minter', state.authority.base.tokenMinter],
          ['ProxyAdmin owner', state.authority.base.proxyAdminOwner],
          ['Timelock delay', state.authority.base.timelockMinDelay ? `${state.authority.base.timelockMinDelay}s` : 'not loaded'],
          ['Recovery disabled', state.authority.base.recoveryDisabled === null ? 'not loaded' : state.authority.base.recoveryDisabled ? 'yes' : 'no'],
          ['Base NTT pauser', state.addresses.base.pauser]
        ]} />
      </section>
      <section className="panel">
        <h2>NTT config</h2>
        <Rows rows={[
          ['Solana mode', state.ntt.solana?.mode],
          ['Solana paused', String(state.ntt.solana?.paused ?? 'not loaded')],
          ['Solana outbound limit', state.ntt.solana?.outboundLimit],
          ['Base mode', state.ntt.base?.mode],
          ['Base paused', String(state.ntt.base?.paused ?? 'not loaded')],
          ['Base outbound limit', state.ntt.base?.outboundLimit],
          ['Transceiver threshold', String(state.ntt.base?.transceiverThreshold ?? 'not loaded')]
        ]} />
      </section>
      <section className="panel wide">
        <h2>Configured authority defaults</h2>
        <Rows rows={[
          ['Timelock proposer', state.authority.configured.timelockProposer],
          ['Timelock executor', state.authority.configured.timelockExecutor],
          ['Timelock admin', state.authority.configured.timelockAdmin],
          ['Initial minter', state.authority.configured.initialMinter]
        ]} />
      </section>
    </div>
  );
}

function Workflow({ state, actions }: { state: CockpitState; actions: CockpitAction[] }) {
  const orderedGroups = ['setup', 'deploy', 'config', 'verify', 'proof', 'artifact'];
  return (
    <div className="workflow-list">
      {orderedGroups.map((group) => (
        <section className="panel" key={group}>
          <h2>{groupLabel(group)}</h2>
          <div className="action-list">
            {actions.filter((item) => item.group === group).map((action) => (
              <ActionCard action={action} key={action.id} state={state} />
            ))}
          </div>
        </section>
      ))}
    </div>
  );
}

function Upgrade({ state, actions }: { state: CockpitState; actions: CockpitAction[] }) {
  return (
    <div className="two-column">
      <section className="panel">
        <h2>Current upgrade surface</h2>
        <Rows rows={[
          ['Proxy', state.addresses.base.token],
          ['Implementation', state.addresses.base.implementation || state.proxy.implementation],
          ['ProxyAdmin', state.addresses.base.proxyAdmin || state.proxy.admin],
          ['ProxyAdmin owner', state.proxy.proxyAdminOwner],
          ['Timelock', state.addresses.base.timelock],
          ['Timelock min delay', state.proxy.timelockMinDelay ? `${state.proxy.timelockMinDelay}s` : 'not loaded']
        ]} />
      </section>
      <section className="panel">
        <h2>Upgrade operations</h2>
        <div className="action-list">
          {actions.map((action) => <ActionCard action={action} key={action.id} state={state} />)}
        </div>
      </section>
    </div>
  );
}

function Recovery({ state, actions }: { state: CockpitState; actions: CockpitAction[] }) {
  return (
    <div className="two-column">
      <section className="panel">
        <h2>Recovery context</h2>
        <Rows rows={[
          ['Base holder', state.addresses.base.deployer],
          ['Base holder GOLD', state.balances.baseDeployerGold],
          ['Base token', state.addresses.base.token],
          ['Solana GOLD mint', state.addresses.solana.token],
          ['Recovery disabled', state.token.recoveryDisabled === null ? 'not loaded' : state.token.recoveryDisabled ? 'yes' : 'no']
        ]} />
      </section>
      <section className="panel">
        <h2>Recovery operations</h2>
        <div className="action-list">
          {actions.map((action) => <ActionCard action={action} key={action.id} state={state} />)}
        </div>
      </section>
    </div>
  );
}

function ActionCard({ action }: { action: CockpitAction; state: CockpitState }) {
  const [env, setEnv] = useState<Record<string, string>>(action.envFields || {});
  const [preview, setPreview] = useState<CockpitActionPreview | null>(null);
  const [confirmation, setConfirmation] = useState('');
  const [result, setResult] = useState<CockpitActionResult | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const fields = useMemo(() => Object.keys(action.envFields || {}), [action.envFields]);

  async function previewNow() {
    setBusy(true);
    setError('');
    setResult(null);
    try {
      setPreview(await previewCockpitAction(action.id, env));
    } catch (err) {
      setError(String((err as Error).message || err));
    } finally {
      setBusy(false);
    }
  }

  async function runNow() {
    setBusy(true);
    setError('');
    try {
      setResult(await runCockpitAction(action.id, env, confirmation));
    } catch (err) {
      setError(String((err as Error).message || err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <article className={`action-card risk-${action.risk}`}>
      <div className="panel-title-row">
        <div>
          <h3>{action.label}</h3>
          <p>{action.description}</p>
        </div>
        <RiskPill risk={action.risk} />
      </div>
      <code>{action.command}</code>
      {fields.length > 0 && (
        <div className="env-grid">
          {fields.map((field) => (
            <label key={field}>
              <span>{field}</span>
              <input value={env[field] || ''} onChange={(event) => setEnv({ ...env, [field]: event.target.value })} />
            </label>
          ))}
        </div>
      )}
      <div className="button-row">
        <button onClick={() => void previewNow()} disabled={busy}>{preview ? 'Preview again' : 'Preview'}</button>
        <button onClick={() => void runNow()} disabled={busy || Boolean(preview?.requiredConfirmation && confirmation !== preview.requiredConfirmation)}>
          {busy ? 'Running' : action.mutates ? 'Run step' : 'Run check'}
        </button>
      </div>
      {preview && (
        <div className="preview-box">
          <Rows rows={[
            ['Working dir', preview.cwd],
            ['Uses local secrets', preview.willUseLocalSecrets ? 'yes' : 'no'],
            ['Confirmation', preview.requiredConfirmation || 'not required']
          ]} />
          {preview.requiredConfirmation && (
            <label className="confirm-field">
              <span>Type confirmation</span>
              <input value={confirmation} onChange={(event) => setConfirmation(event.target.value)} placeholder={preview.requiredConfirmation} />
            </label>
          )}
        </div>
      )}
      {error && <p className="warning">{error}</p>}
      {result && (
        <div className={result.ok ? 'result-box ok' : 'result-box failed'}>
          <strong>{result.ok ? 'Completed' : `Failed with exit ${result.exitCode}`}</strong>
          <pre>{[result.stdout, result.stderr].filter(Boolean).join('\n')}</pre>
        </div>
      )}
    </article>
  );
}

function TransactionRows({ state }: { state: CockpitState }) {
  const baseExplorer = state.addresses.base.explorerUrl;
  const rows: Array<[string, string | undefined, string?]> = [
    ['Base token deploy', state.transactions.baseTokenDeploy, state.transactions.baseTokenDeploy ? evmExplorerTx(baseExplorer, state.transactions.baseTokenDeploy) : ''],
    ['Base set minter', state.transactions.baseSetMinter, state.transactions.baseSetMinter ? evmExplorerTx(baseExplorer, state.transactions.baseSetMinter) : ''],
    ['Solana to Base proof', state.transactions.solanaToBaseProof, state.transactions.solanaToBaseProof ? solanaExplorerTx(state.transactions.solanaToBaseProof, state.addresses.solana.explorerCluster) : ''],
    ['Base to Solana approve', state.transactions.baseToSolanaApprove, state.transactions.baseToSolanaApprove ? evmExplorerTx(baseExplorer, state.transactions.baseToSolanaApprove) : ''],
    ['Base to Solana proof', state.transactions.baseToSolanaProof, state.transactions.baseToSolanaProof ? evmExplorerTx(baseExplorer, state.transactions.baseToSolanaProof) : '']
  ];
  return <Rows rows={rows} />;
}

function Rows({ rows }: { rows: Array<[string, string | undefined, string?]> }) {
  return (
    <div className="rows">
      {rows.map(([label, value, href]) => (
        <div className="data-row" key={label}>
          <span>{label}</span>
          {href && value ? <a href={href} target="_blank" rel="noreferrer">{shortenAddress(value, 8)}</a> : <strong>{value || 'not set'}</strong>}
        </div>
      ))}
    </div>
  );
}

function Metric({ title, value }: { title: string; value: string }) {
  return (
    <section className="panel metric-panel">
      <span>{title}</span>
      <strong>{value}</strong>
    </section>
  );
}

function StatusPill({ ok, label }: { ok: boolean; label: string }) {
  return <span className={ok ? 'status-pill ok' : 'status-pill warn'}>{label}</span>;
}

function RiskPill({ risk }: { risk: string }) {
  return <span className={`risk-pill risk-${risk}`}>{risk}</span>;
}

function groupLabel(group: string) {
  const labels: Record<string, string> = {
    setup: 'Local setup',
    deploy: 'Deploy',
    config: 'Configure',
    verify: 'Verify',
    proof: 'Proof transfers',
    artifact: 'Artifacts'
  };
  return labels[group] || group;
}
