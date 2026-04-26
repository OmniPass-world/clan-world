import React from 'react';
import ReactDOM from 'react-dom/client';
import { ConvexProvider, ConvexReactClient } from 'convex/react';
import { MiniKit } from '@worldcoin/minikit-js';
import { App } from './App';

// MiniKit v2: install() must be called before rendering in the World App webview.
// No MiniKitProvider component in v2 — install() is a static class call.
// Guard against undefined APP_ID (e.g. env not baked into prod bundle): calling
// install(undefined) in older builds shipped a literal `void 0` and broke the
// page on first navigation. Skip install if missing — MiniKit.isInstalled()
// will return false and App will render its "Open in World App" fallback.
const worldAppId = import.meta.env.VITE_WORLD_APP_ID as string | undefined;
if (worldAppId) {
  try {
    MiniKit.install(worldAppId as `app_${string}`);
  } catch (err) {
    console.error('MiniKit.install failed:', err);
  }
} else {
  console.warn('VITE_WORLD_APP_ID not set — MiniKit not installed');
}

// Telegram Mini App fullscreen: hide the platform top chrome (the bar that
// shows the app title + V down-arrow). Available in Telegram Mini App API
// v8.0+. Falls back to expand() on older clients. Wrapped in try/catch so a
// missing API or unsupported platform never blocks render.
type TgWebApp = {
  ready?: () => void;
  expand?: () => void;
  requestFullscreen?: () => void;
  isVersionAtLeast?: (v: string) => boolean;
};
const tg: TgWebApp | undefined = (window as unknown as { Telegram?: { WebApp?: TgWebApp } }).Telegram?.WebApp;
if (tg) {
  try {
    tg.ready?.();
    tg.expand?.();
    if (tg.isVersionAtLeast?.('8.0') && tg.requestFullscreen) {
      tg.requestFullscreen();
    } else if (tg.requestFullscreen) {
      // Some builds don't expose isVersionAtLeast — try anyway, swallow errors.
      try { tg.requestFullscreen(); } catch { /* unsupported */ }
    }
  } catch (err) {
    console.warn('Telegram WebApp fullscreen init failed:', err);
  }
}

const convexUrl = import.meta.env.VITE_CONVEX_URL as string | undefined;

// Cast required: convex's React.FC type conflicts with @types/react@18.3 ReactNode (bigint addition)
const Provider = ConvexProvider as React.ComponentType<{
  client: ConvexReactClient;
  children?: React.ReactNode;
}>;

const root = ReactDOM.createRoot(document.getElementById('root')!);

if (!convexUrl) {
  // Fail soft instead of throwing — a thrown error here leaves a blank page,
  // which is unacceptable for the hackathon submission. Render a visible
  // message so the user sees something even if the build is misconfigured.
  console.error('VITE_CONVEX_URL is not set — rendering degraded fallback');
  root.render(
    <main
      style={{
        background: '#0d1a0d',
        minHeight: '100vh',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        padding: '24px',
        textAlign: 'center',
      }}
    >
      <div
        style={{
          color: 'white',
          fontFamily: 'monospace',
          maxWidth: '420px',
        }}
      >
        <h1 style={{ margin: 0, fontSize: '20px' }}>ClanWorld</h1>
        <p style={{ marginTop: '12px', opacity: 0.8 }}>
          Backend not configured. Open in the World App or contact the team.
        </p>
      </div>
    </main>,
  );
} else {
  const convex = new ConvexReactClient(convexUrl);
  root.render(
    <React.StrictMode>
      <Provider client={convex}>
        <App />
      </Provider>
    </React.StrictMode>,
  );
}
