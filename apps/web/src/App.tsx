import type { WorldSnapshot } from '@clan-world/shared';

const mockSnapshot: WorldSnapshot = {
  tick: 0,
  tickEpoch: { startedAt: 0, durationMs: 20_000 },
  regions: [],
  clans: [],
};

export function App() {
  return (
    <main style={{ fontFamily: 'system-ui, sans-serif', padding: '2rem' }}>
      <h1>Hello ClanWorld</h1>
      <p>Wave 0 placeholder. Mock snapshot:</p>
      <pre style={{ background: '#f6f6f6', padding: '1rem', borderRadius: 8 }}>
        {JSON.stringify(mockSnapshot, null, 2)}
      </pre>
    </main>
  );
}
