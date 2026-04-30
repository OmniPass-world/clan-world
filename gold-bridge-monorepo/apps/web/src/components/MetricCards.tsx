import { useEffect, useState } from 'react';
import { fetchMetrics } from '../lib/metrics';
import type { MetricSnapshot } from '../types';

export function MetricCards() {
  const [metrics, setMetrics] = useState<MetricSnapshot | null>(null);
  const [loading, setLoading] = useState(false);

  async function refresh() {
    setLoading(true);
    try {
      setMetrics(await fetchMetrics());
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    void refresh();
  }, []);

  return (
    <section className="card">
      <div className="card-title-row">
        <h2>Supplies</h2>
        <button onClick={() => void refresh()} disabled={loading}>{loading ? 'Refreshing' : 'Refresh'}</button>
      </div>
      <div className="metric-grid">
        <div className="metric">
          <span>Solana GOLD supply</span>
          <strong>{metrics?.solanaSupplyUi ?? 'not loaded'}</strong>
        </div>
        <div className="metric">
          <span>Base GOLD supply</span>
          <strong>{metrics?.baseSupplyUi ?? 'not loaded'}</strong>
        </div>
      </div>
      {metrics?.updatedAt && <p className="muted">Updated {new Date(metrics.updatedAt).toLocaleString()}</p>}
      {metrics?.error && <p className="warning">{metrics.error}</p>}
    </section>
  );
}
