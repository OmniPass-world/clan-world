import { useEffect, useState } from 'react';
import { MiniKit } from '@worldcoin/minikit-js';
import { useIDKitRequest } from '@worldcoin/idkit';
import type { IDKitRequestHookConfig } from '@worldcoin/idkit';
import { WorldMap } from './WorldMap';

// Convex HTTP actions are served at <deployment>.convex.site (not .convex.cloud)
const CONVEX_SITE_URL =
  (import.meta.env.VITE_CONVEX_URL as string | undefined)?.replace(
    '.convex.cloud',
    '.convex.site',
  ) ?? '';

const APP_ID = import.meta.env.VITE_WORLD_APP_ID as `app_${string}`;
const ACTION_ID =
  (import.meta.env.VITE_WORLD_ACTION_ID as string | undefined) ?? 'clan-join';

// Stub rp_context satisfies the TypeScript type requirement.
// With the orbLegacy preset + allow_legacy_proofs the World App postMessage
// transport is used in-app; rp_context is not validated server-side for legacy flows.
const STUB_RP_CONTEXT: IDKitRequestHookConfig['rp_context'] = {
  rp_id: (import.meta.env.VITE_WORLD_RP_ID as string | undefined) ?? '',
  nonce: '0',
  created_at: 0,
  expires_at: 2147483647,
  signature: '0x',
};

const IDKIT_CONFIG: IDKitRequestHookConfig = {
  app_id: APP_ID,
  action: ACTION_ID,
  rp_context: STUB_RP_CONTEXT,
  allow_legacy_proofs: true,
  preset: { type: 'OrbLegacy' },
};

// Demo-mode escape hatch: when set to the string 'true' at build time, the
// "Open in World App to play" guard below is skipped so the full canvas + UI
// renders in any browser (for Loom recording / judges testing). The guard is
// the production default — only the explicit env opt-in disables it.
const DEMO_BYPASS_WORLD_GUARD =
  import.meta.env.VITE_DEMO_BYPASS_WORLD_GUARD === 'true';

export function App() {
  // When the demo bypass env is set, start verified=true so the WorldMap canvas
  // renders immediately without an IDKit verify round-trip (which can't complete
  // outside World App). Production default (env unset) keeps the full gate.
  const [verified, setVerified] = useState(DEMO_BYPASS_WORLD_GUARD);
  const isInWorldApp = MiniKit.isInstalled() || DEMO_BYPASS_WORLD_GUARD;

  const { open: openIDKit, result, isSuccess } = useIDKitRequest(IDKIT_CONFIG);

  useEffect(() => {
    if (!isSuccess || result === null) return;
    if (!CONVEX_SITE_URL) {
      console.error('CONVEX_SITE_URL not set — VITE_CONVEX_URL missing');
      return;
    }
    fetch(`${CONVEX_SITE_URL}/api/verify`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(result),
    })
      .then((res) => {
        if (res.ok) {
          setVerified(true);
        } else {
          console.error('Verify failed:', res.status);
        }
      })
      .catch((err) => console.error('Verify error:', err));
  }, [isSuccess, result]);

  if (!isInWorldApp) {
    return (
      <main
        style={{
          background: '#0a0a0a',
          width: '100vw',
          height: '100vh',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
        }}
      >
        <p style={{ color: 'white', fontFamily: '"Cinzel", "Times New Roman", serif', letterSpacing: '0.08em' }}>
          Open in World App to play
        </p>
      </main>
    );
  }

  return (
    <main
      style={{
        background: '#0a0a0a',
        width: '100vw',
        height: '100vh',
        display: 'flex',
        flexDirection: 'column',
        overflow: 'hidden',
      }}
    >
      {/* Page title removed — host chrome (Telegram / World App) shows the app name. */}
      {!verified && (
        <button
          onClick={openIDKit}
          style={{
            margin: '8px',
            padding: '12px 24px',
            fontFamily: 'monospace',
            cursor: 'pointer',
          }}
        >
          Claim Your Clan Identity
        </button>
      )}
      {verified && <WorldMap />}
    </main>
  );
}
