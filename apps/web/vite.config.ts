import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'node:path';

// Port allocation per ~/claudes-world ADR 0003 (project-sharded). Use port-for at dev time;
// for now read from env to avoid hard-coding before the slot is registered.
//
// envDir: load .env.local from the monorepo root, not the web app folder.
// .env.local lives at <repo-root>/.env.local and is shared with server/agents.
// Without this, VITE_* values are undefined at build time and the prod bundle
// has no Convex URL / World App ID baked in (white screen).
export default defineConfig({
  plugins: [react()],
  envDir: path.resolve(__dirname, '../..'),
  server: {
    port: Number(process.env.PORT ?? 5173),
    host: '127.0.0.1',
  },
});
