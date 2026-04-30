import WormholeConnect from '@wormhole-foundation/wormhole-connect';
import { makeWormholeConnectConfig } from '../config/wormholeConnect';

export function BridgePanel() {
  const config = makeWormholeConnectConfig();

  if (!config) {
    return (
      <section className="card bridge-card">
        <h2>Bridge</h2>
        <p>
          The bridge widget appears after NTT manager and transceiver addresses are generated.
          Run the deployment scripts, then run the frontend config export script.
        </p>
      </section>
    );
  }

  return (
    <section className="card bridge-card">
      <WormholeConnect config={config} />
    </section>
  );
}
