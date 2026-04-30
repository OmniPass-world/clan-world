import { BridgePanel } from './components/BridgePanel';
import { BridgeHistory } from './components/BridgeHistory';
import { ExplorerLinks } from './components/ExplorerLinks';
import { MetricCards } from './components/MetricCards';
import { SetupChecklist } from './components/SetupChecklist';
import { goldDeployment } from './generated/goldDeployment';
import './styles.css';

export default function App() {
  return (
    <main className="app-shell">
      <header className="hero">
        <div>
          <p className="eyebrow">Wormhole NTT</p>
          <h1>{goldDeployment.tokenSymbol} Bridge</h1>
          <p>
            Bridge canonical Solana {goldDeployment.tokenSymbol} to Base using Solana locking mode and Base burning mode.
          </p>
        </div>
        <div className="network-pill">{goldDeployment.network}</div>
      </header>

      <div className="layout">
        <div className="main-column">
          <BridgePanel />
          <BridgeHistory />
        </div>
        <aside className="side-column">
          <SetupChecklist />
          <ExplorerLinks />
          <MetricCards />
        </aside>
      </div>
    </main>
  );
}
