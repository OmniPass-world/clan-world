/**
 * Reject inbox keys that aren't a single safe path segment. A clan id of `..`
 * or `foo/bar` or anything containing a path separator could escape the
 * `peer-inbox` directory when interpolated into a filename.
 */
export function assertSafeInboxKey(key: string): void {
  if (!/^[A-Za-z0-9_-]+$/.test(key)) {
    throw new Error(`unsafe inbox key '${key}' - must be alphanumeric + '-_' only`);
  }
}
