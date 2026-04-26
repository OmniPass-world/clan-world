import { WorldMap } from './WorldMap';

export function App() {
  return (
    <main style={{ background: '#0d1a0d', minHeight: '100vh' }}>
      <h1 style={{ color: 'white', fontFamily: 'monospace', padding: '8px' }}>ClanWorld v0.2.0</h1>
      <WorldMap />
    </main>
  );
}
