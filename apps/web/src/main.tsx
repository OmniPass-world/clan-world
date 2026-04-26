import React from 'react';
import ReactDOM from 'react-dom/client';
import { ConvexProvider, ConvexReactClient } from 'convex/react';
import { MiniKit } from '@worldcoin/minikit-js';
import { App } from './App';

// MiniKit v2: install() must be called before rendering in the World App webview.
// No MiniKitProvider component in v2 — install() is a static class call.
MiniKit.install(import.meta.env.VITE_WORLD_APP_ID);

const convexUrl = import.meta.env.VITE_CONVEX_URL;
if (!convexUrl) throw new Error('VITE_CONVEX_URL is not set');
const convex = new ConvexReactClient(convexUrl);

// Cast required: convex's React.FC type conflicts with @types/react@18.3 ReactNode (bigint addition)
const Provider = ConvexProvider as React.ComponentType<{ client: ConvexReactClient; children?: React.ReactNode }>;

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <Provider client={convex}>
      <App />
    </Provider>
  </React.StrictMode>,
);
