import fs from 'node:fs';
import path from 'node:path';
import type { IElderMemoryStore } from '@clan-world/agents/seams';
import type { ElderId } from './types';

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
 */
export class FileMemoryStore implements IElderMemoryStore {
  private readonly file: string;

  constructor(elder: ElderId, stateDir: string) {
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
    // Write to a temp file then rename for atomic durability.
    const tmp = `${this.file}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify(data, null, 2) + '\n', 'utf8');
    fs.renameSync(tmp, this.file);
  }
}
