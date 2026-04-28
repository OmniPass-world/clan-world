/**
 * FileMemoryStore — S2 local-file implementation of IElderMemoryStore.
 *
 * Stores key/value pairs in a JSON file at:
 *   <stateDir>/elder-{N}-memory.json
 *
 * Used as the fallback when OG_STORAGE_API_KEY is not set.
 */
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import type { IElderMemoryStore } from '@clan-world/agents/src/seams/index.js';

export function defaultStateDir(base: string = os.homedir()): string {
  return path.join(base, '.world', 'clanworld-runner', 'state');
}

export class FileMemoryStore implements IElderMemoryStore {
  private readonly filePath: string;

  constructor(elderN: number, stateDir: string = defaultStateDir()) {
    this.filePath = path.join(stateDir, `elder-${elderN}-memory.json`);
  }

  async recall(key: string): Promise<string | undefined> {
    const data = this.#read();
    return data[key];
  }

  async save(key: string, value: string): Promise<void> {
    const data = this.#read();
    data[key] = value;
    this.#write(data);
  }

  async snapshot(): Promise<Record<string, string>> {
    return this.#read();
  }

  #read(): Record<string, string> {
    if (!fs.existsSync(this.filePath)) return {};
    try {
      return JSON.parse(fs.readFileSync(this.filePath, 'utf8')) as Record<string, string>;
    } catch {
      return {};
    }
  }

  #write(data: Record<string, string>): void {
    const dir = path.dirname(this.filePath);
    fs.mkdirSync(dir, { recursive: true });
    // Write to a temp file then rename for an atomic update on POSIX systems.
    // Prevents JSON corruption if two processes write concurrently or the process
    // crashes mid-write.
    const tmpPath = this.filePath + '.tmp';
    fs.writeFileSync(tmpPath, JSON.stringify(data, null, 2) + '\n', 'utf8');
    fs.renameSync(tmpPath, this.filePath);
  }
}
