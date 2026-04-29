import fs from 'node:fs';

const RESTRICTED_MODE = 0o600;

export function writeRestrictedFileSync(
  file: string,
  data: string,
  options: Omit<fs.WriteFileOptions, 'mode'> = {},
): void {
  fs.writeFileSync(file, data, {
    ...options,
    mode: RESTRICTED_MODE,
  });
  fs.chmodSync(file, RESTRICTED_MODE);
}

export function appendRestrictedFileSync(
  file: string,
  data: string,
  options: Omit<fs.WriteFileOptions, 'mode'> = {},
): void {
  fs.appendFileSync(file, data, {
    ...options,
    mode: RESTRICTED_MODE,
  });
  fs.chmodSync(file, RESTRICTED_MODE);
}
