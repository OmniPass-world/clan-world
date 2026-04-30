import { useEffect, useState } from 'react';
import type { HistoryItem } from '../types';
import { addLocalHistory, fetchWormholescanHistory, readLocalHistory } from '../lib/history';

export function BridgeHistory() {
  const [remoteHistory, setRemoteHistory] = useState<HistoryItem[]>([]);
  const [localHistory, setLocalHistory] = useState<HistoryItem[]>([]);
  const [error, setError] = useState('');

  async function refresh() {
    setError('');
    setLocalHistory(readLocalHistory());
    try {
      setRemoteHistory(await fetchWormholescanHistory());
    } catch (err) {
      setError(String((err as Error).message || err));
    }
  }

  function addNote() {
    const amount = prompt('Amount, for example 1.25 GOLD') || '';
    if (!amount) return;
    const direction = prompt('Direction, for example Solana to Base') || 'manual note';
    addLocalHistory({ amount, direction, status: 'Manual note' });
    setLocalHistory(readLocalHistory());
  }

  useEffect(() => {
    void refresh();
  }, []);

  return (
    <section className="card">
      <div className="card-title-row">
        <h2>Bridge history</h2>
        <div className="button-row">
          <button onClick={() => void refresh()}>Refresh</button>
          <button onClick={addNote}>Add local note</button>
        </div>
      </div>
      <h3>Wormholescan activity</h3>
      {error && <p className="warning">Wormholescan history unavailable: {error}</p>}
      <HistoryList items={remoteHistory} empty="No indexed Wormholescan activity found yet." />
      <h3>Browser-local notes</h3>
      <HistoryList items={localHistory} empty="No local notes yet." />
    </section>
  );
}

function HistoryList({ items, empty }: { items: HistoryItem[]; empty: string }) {
  if (!items.length) return <p className="muted">{empty}</p>;
  return (
    <div className="history-list">
      {items.map((item) => (
        <div className="history-item" key={item.id}>
          <strong>{item.direction}</strong>
          <span>{item.amount}</span>
          <span>{item.status}</span>
          <small>{new Date(item.timestamp).toLocaleString()}</small>
        </div>
      ))}
    </div>
  );
}
