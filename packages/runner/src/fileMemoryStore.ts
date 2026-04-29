import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import type { IElderMemoryStore } from '@clan-world/agents/seams';

/**
 * Default state dir for the runner — `~/.world/clanworld-runner/state`.
 * Matches the path the Elder CLI reads/writes; exported so the 0G adapter
 * can fall back to a local file under the same directory.
 */
export function defaultStateDir(base: string = os.homedir()): string {
  return path.join(base, '.world', 'clanworld-runner', 'state');
}

/**
 * S2 stub of `IElderMemoryStore` backed by a per-Elder JSON file.
 *
 * File: `${stateDir}/elder-{N}-memory.json`
 *
 * Single-writer assumption: only ONE process should hold a `FileMemoryStore`
 * for a given Elder at a time. The runner satisfies this naturally — there is
 * a single daemon. The Elder CLI (`elder memory save/recall`) reads + writes
 * the same file but is invoked synchronously from inside the Elder's tmux
 * session, so writes do not race the runner's writes.
 *
 * Atomic write: data is written to a randomly-suffixed temp file then renamed
 * onto the target so concurrent writers (e.g. runner + Elder CLI) do not
 * corrupt the JSON document.
 */
export class FileMemoryStore implements IElderMemoryStore {
  private readonly file: string;

  constructor(elder: number, stateDir: string = defaultStateDir()) {
    this.file = path.join(stateDir, `elder-${elder}-memory.json`);
  }

  async recall(key: string): Promise<string | undefined> {
    const data = this.read();
    return data[key];
  }

  async save(key: string, value: string): Promise<void> {
    const data = this.read();
    data[key] = value;
    this.write(data);
  }

  async snapshot(): Promise<Record<string, string>> {
    return this.read();
  }

  private read(): Record<string, string> {
    if (!fs.existsSync(this.file)) return {};
    try {
      const raw = fs.readFileSync(this.file, 'utf8');
      return JSON.parse(raw) as Record<string, string>;
    } catch {
      // Corrupt file: treat as empty so the Elder can recover. We deliberately
      // swallow the parse error here — a corrupt memory file should not crash
      // the tick loop. The next `save()` will overwrite with a valid JSON doc.
      return {};
    }
  }

  private write(data: Record<string, string>): void {
    fs.mkdirSync(path.dirname(this.file), { recursive: true });
    // Write to a randomly-suffixed temp file then rename for atomic durability.
    // Random suffix prevents concurrent-process collisions on the temp path.
    const suffix = Math.random().toString(36).slice(2);
    const tmp = `${this.file}.${suffix}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify(data, null, 2) + '\n', {
      encoding: 'utf8',
      mode: 0o600,
    });
    fs.renameSync(tmp, this.file);
  }
}
