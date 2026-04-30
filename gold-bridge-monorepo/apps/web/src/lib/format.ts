export function shortenAddress(address: string, chars = 6) {
  if (!address) return 'not set';
  if (address.length <= chars * 2 + 3) return address;
  return `${address.slice(0, chars)}…${address.slice(-chars)}`;
}

export function formatUnits(raw: string | bigint, decimals: number) {
  const value = typeof raw === 'bigint' ? raw.toString() : raw;
  if (!value || value === '0') return '0';
  if (decimals <= 0) return value;
  const negative = value.startsWith('-');
  const digits = negative ? value.slice(1) : value;
  const padded = digits.padStart(decimals + 1, '0');
  const whole = padded.slice(0, -decimals);
  const fraction = padded.slice(-decimals).replace(/0+$/, '');
  return `${negative ? '-' : ''}${whole}${fraction ? `.${fraction}` : ''}`;
}

export function solanaExplorerAddress(address: string, cluster?: string) {
  const suffix = cluster ? `?cluster=${encodeURIComponent(cluster)}` : '';
  return `https://solscan.io/account/${address}${suffix}`;
}

export function solanaExplorerTx(tx: string, cluster?: string) {
  const suffix = cluster ? `?cluster=${encodeURIComponent(cluster)}` : '';
  return `https://solscan.io/tx/${tx}${suffix}`;
}

export function evmExplorerAddress(baseUrl: string, address: string) {
  return `${baseUrl.replace(/\/$/, '')}/address/${address}`;
}

export function evmExplorerTx(baseUrl: string, tx: string) {
  return `${baseUrl.replace(/\/$/, '')}/tx/${tx}`;
}
