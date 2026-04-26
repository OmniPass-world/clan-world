// Browser-safe env getter. Reads process.env in Node and import.meta.env in Vite.
// Vite only exposes vars prefixed with VITE_ to the browser bundle. This helper
// tries both the bare name and the VITE_-prefixed name in each context so callers
// can use the same key (e.g. 'CLAN_WORLD_USE_STUB_CONVEX') in Node and Vite.
//
// Resolution order (first defined value wins):
//   1. process.env[name]           — Node / tsx, unprefixed
//   2. process.env['VITE_'+name]   — Node / tsx, VITE_-prefixed (e.g. loaded via dotenv)
//   3. import.meta.env[name]       — Vite build, bare (unlikely to be exposed)
//   4. import.meta.env['VITE_'+name] — Vite build happy path

declare const process: { env?: Record<string, string | undefined> } | undefined;

export function readEnv(name: string): string | undefined {
  // Node / tsx — try bare then VITE_-prefixed
  if (typeof process !== 'undefined' && process.env) {
    const v = process.env[name];
    if (v !== undefined) return v;
    const vv = process.env['VITE_' + name];
    if (vv !== undefined) return vv;
  }
  // Vite browser bundle (import.meta.env is statically expanded by Vite)
  try {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const meta = (import.meta as any).env as Record<string, string | undefined> | undefined;
    if (meta) {
      const v = meta[name];
      if (v !== undefined) return v;
      return meta['VITE_' + name];
    }
  } catch {
    /* import.meta unsupported */
  }
  return undefined;
}
