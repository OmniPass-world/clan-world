// Browser-safe env getter. Reads process.env in Node and import.meta.env in Vite.
// Vite inlines `import.meta.env.VAR` at build time when used directly; this helper
// is the runtime fallback for adapter factories that may run on either side.

declare const process: { env?: Record<string, string | undefined> } | undefined;

export function readEnv(name: string): string | undefined {
  // Node / tsx
  if (typeof process !== 'undefined' && process.env) {
    const v = process.env[name];
    if (v !== undefined) return v;
  }
  // Vite browser bundle (import.meta.env is statically expanded by Vite)
  try {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const meta = (import.meta as any).env as Record<string, string | undefined> | undefined;
    if (meta) return meta[name];
  } catch {
    /* import.meta unsupported */
  }
  return undefined;
}
