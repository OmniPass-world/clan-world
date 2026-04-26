import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// Port allocation per ~/claudes-world ADR 0003 (project-sharded). Use port-for at dev time;
// for now read from env to avoid hard-coding before the slot is registered.
export default defineConfig({
  plugins: [react()],
  server: {
    port: Number(process.env.PORT ?? 5174),
    host: '127.0.0.1',
  },
});
