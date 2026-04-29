import { useEffect, useState } from 'react';
import { MiniKit } from '@worldcoin/minikit-js';
import { useIDKitRequest } from '@worldcoin/idkit';
import type { IDKitRequestHookConfig } from '@worldcoin/idkit';
import { WorldMap } from './WorldMap';
import { Cockpit } from './pages/Cockpit';
import { WorldMapBoundary } from './components/cockpit/shared/WorldMapBoundary';

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

// Env flags moved to ./config/env to break the WorldMap ↔ App circular
// dependency (PR #133 review MUST FIX #3). Re-exported here for any external
// callers; new internal callers should import directly from ./config/env.
import { DEMO_MODE, DEMO_BYPASS_WORLD_GUARD } from './config/env';
export { DEMO_MODE };

/**
 * Top-level route decision. Lightweight path-based routing avoids a router
 * dep for a single side route. Reading window.location once at render is
 * fine here — the cockpit is a standalone judge view, not a SPA tab inside
 * the main app, so we never need to navigate between them client-side.
 */
function isCockpitRoute(): boolean {
  return (
    typeof window !== 'undefined' &&
    window.location.pathname.startsWith('/cockpit')
  );
}

export function App() {
  // /cockpit route — standalone judge view, bypasses World App / verify gate.
  // Pure read-only frontend for now (Phase B will wire live data).
  // Routed BEFORE any hooks so the cockpit branch never instantiates the
  // World-App / IDKit hooks (which would warn about missing config in a
  // plain browser).
  if (isCockpitRoute()) {
    return <Cockpit />;
  }
  return <MainApp />;
}

function MainApp() {
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
    const worldAppDeeplink = APP_ID
      ? `https://world.org/mini-app?app_id=${APP_ID}`
      : 'https://world.org/download';
    return (
      <main
        style={{
          background: '#0a0a0a',
          width: '100vw',
          height: '100vh',
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
          padding: '24px',
          color: 'white',
          fontFamily: '"Cinzel", "Times New Roman", serif',
        }}
      >
        <h1 style={{ fontSize: '2rem', letterSpacing: '0.12em', marginBottom: '12px', textAlign: 'center' }}>
          Clan World
        </h1>
        <p style={{ fontSize: '1rem', letterSpacing: '0.06em', maxWidth: '420px', textAlign: 'center', lineHeight: 1.5, marginBottom: '24px', opacity: 0.85 }}>
          This experience runs inside the World App. Tap below on a phone that has World App installed.
        </p>
        <a
          href={worldAppDeeplink}
          target="_blank"
          rel="noopener noreferrer"
          style={{
            display: 'inline-block',
            padding: '14px 28px',
            background: '#7a8a6a',
            color: 'white',
            textDecoration: 'none',
            borderRadius: '4px',
            fontFamily: 'monospace',
            fontSize: '0.95rem',
            letterSpacing: '0.08em',
            marginBottom: '12px',
          }}
        >
          Open in World App →
        </a>
        <p style={{ fontSize: '0.8rem', opacity: 0.5, textAlign: 'center', maxWidth: '360px', marginTop: '16px' }}>
          Don't have World App? <a href="https://world.org/download" target="_blank" rel="noopener noreferrer" style={{ color: '#9bbf6f', textDecoration: 'underline' }}>Get it here</a>.
        </p>
        <p style={{ fontSize: '0.7rem', opacity: 0.4, textAlign: 'center', marginTop: '24px', fontFamily: 'monospace' }}>
          For local dev: set <code>VITE_DEMO_BYPASS_WORLD_GUARD=true</code> or run <code>pnpm dev</code> (already set).
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
      {verified && (
        <WorldMapBoundary>
          <WorldMap />
        </WorldMapBoundary>
      )}
    </main>
  );
}
