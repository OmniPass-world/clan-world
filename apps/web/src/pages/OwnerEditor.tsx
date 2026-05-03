import { useCallback, useMemo, useState } from 'react';
import {
  CLAN_AGENT_NFT_ABI,
  hashIntelligentData,
  type IntelligentDataEntry,
} from '@clan-world/shared/adapters';
import {
  createPublicClient,
  createWalletClient,
  custom,
  defineChain,
  http,
  keccak256,
  stringToHex,
  type Address,
  type EIP1193Provider,
  type Hex,
} from 'viem';

declare global {
  interface Window {
    ethereum?: unknown;
  }
}

const OG_INFT_ADDRESS = import.meta.env.VITE_OG_INFT_ADDRESS as Address | undefined;
const OG_RPC_URL = (import.meta.env.VITE_OG_RPC_URL as string | undefined) ?? 'https://evmrpc.0g.ai';
const OG_CHAIN_ID = Number(import.meta.env.VITE_OG_CHAIN_ID ?? 16661);

const ogChain = defineChain({
  id: OG_CHAIN_ID,
  name: '0G',
  nativeCurrency: { name: '0G', symbol: '0G', decimals: 18 },
  rpcUrls: { default: { http: [OG_RPC_URL] } },
});

const proofHex = (value: string): Hex => stringToHex(value.length > 0 ? value : 'demo-proof');
const hashText = (value: string): Hex => keccak256(stringToHex(value));
const demoStorageKey = (tokenId: bigint) => `clanworld:inft-demo:${tokenId.toString()}`;

function demoData(tokenId: bigint, notes: string): IntelligentDataEntry[] {
  return [
    {
      label: 'persona',
      dataHash: hashText(`elder-${tokenId}:persona`),
      uri: `0g://clanworld/clan/${tokenId}/persona`,
    },
    {
      label: 'memory',
      dataHash: hashText(`elder-${tokenId}:memory:${notes}`),
      uri: `0g://clanworld/clan/${tokenId}/memory`,
    },
    {
      label: 'owner_notes',
      dataHash: hashText(notes),
      uri: `0g://clanworld/clan/${tokenId}/owner-notes`,
    },
  ];
}

export function OwnerEditor() {
  const [tokenIdText, setTokenIdText] = useState('7');
  const [owner, setOwner] = useState<Address | 'demo-owner'>('demo-owner');
  const [newOwner, setNewOwner] = useState('');
  const [notes, setNotes] = useState('Clan 3 betrayed us before transfer. Do not trust their river offers.');
  const [data, setData] = useState<IntelligentDataEntry[]>(() => demoData(7n, notes));
  const [txLog, setTxLog] = useState<string[]>([]);
  const [busy, setBusy] = useState(false);

  const tokenId = useMemo(() => {
    try {
      return BigInt(tokenIdText || '0');
    } catch {
      return 0n;
    }
  }, [tokenIdText]);

  const currentHash = useMemo(() => hashIntelligentData(data), [data]);

  const publicClient = useMemo(
    () => createPublicClient({ chain: ogChain, transport: http(OG_RPC_URL) }),
    [],
  );

  const appendLog = (line: string) => setTxLog((prev) => [line, ...prev].slice(0, 8));
  const persistDemoState = useCallback((nextOwner: Address | 'demo-owner', nextData: IntelligentDataEntry[]) => {
    if (typeof window === 'undefined' || tokenId === 0n) return;
    window.localStorage.setItem(
      demoStorageKey(tokenId),
      JSON.stringify({
        tokenId: tokenId.toString(),
        owner: nextOwner,
        dataHash: hashIntelligentData(nextData),
        data: nextData,
        notes,
        updatedAt: Date.now(),
      }),
    );
  }, [notes, tokenId]);

  const loadToken = useCallback(async () => {
    if (!OG_INFT_ADDRESS || tokenId === 0n) {
      const fallback = demoData(tokenId || 7n, notes);
      setData(fallback);
      setOwner('demo-owner');
      persistDemoState('demo-owner', fallback);
      appendLog('Loaded demo iNFT state');
      return;
    }
    setBusy(true);
    try {
      const [tokenOwner, intelligentData] = await Promise.all([
        publicClient.readContract({
          address: OG_INFT_ADDRESS,
          abi: CLAN_AGENT_NFT_ABI,
          functionName: 'ownerOf',
          args: [tokenId],
        }),
        publicClient.readContract({
          address: OG_INFT_ADDRESS,
          abi: CLAN_AGENT_NFT_ABI,
          functionName: 'intelligentDataOf',
          args: [tokenId],
        }),
      ]);
      setOwner(tokenOwner);
      setData(intelligentData.map((entry) => ({ label: entry.label, dataHash: entry.dataHash, uri: entry.uri })));
      persistDemoState(tokenOwner, intelligentData.map((entry) => ({ label: entry.label, dataHash: entry.dataHash, uri: entry.uri })));
      appendLog(`Loaded token ${tokenId}`);
    } catch (err) {
      // Clear stale state on failure so the UI never shows last-token's owner/data
      // mapped to a different tokenId. Demo: judges typing an unminted ID see
      // demo-owner + canonical demo data, not stale stand-ins from a prior load.
      const fallback = demoData(tokenId || 7n, notes);
      setOwner('demo-owner');
      setData(fallback);
      persistDemoState('demo-owner', fallback);
      appendLog(`Load failed: ${(err as Error).message}`);
    } finally {
      setBusy(false);
    }
  }, [notes, publicClient, tokenId]);

  const walletClient = useCallback(async () => {
    if (!window.ethereum) throw new Error('No injected wallet found');
    const client = createWalletClient({ chain: ogChain, transport: custom(window.ethereum as EIP1193Provider) });
    const [account] = await client.requestAddresses();
    if (!account) throw new Error('Wallet returned no account');
    return { client, account };
  }, []);

  const updateMetadata = useCallback(async () => {
    const nextData = demoData(tokenId, notes);
    if (!OG_INFT_ADDRESS) {
      // Pure demo mode — no chain, persist locally so the cockpit reflects.
      setData(nextData);
      persistDemoState(owner, nextData);
      appendLog(`Prepared metadata hash ${hashIntelligentData(nextData).slice(0, 12)}...`);
      return;
    }
    setBusy(true);
    try {
      const { client, account } = await walletClient();
      const tx = await client.writeContract({
        account,
        address: OG_INFT_ADDRESS,
        abi: CLAN_AGENT_NFT_ABI,
        functionName: 'updateMetadata',
        args: [tokenId, nextData, proofHex(`metadata:${tokenId}:${notes}`)],
      });
      appendLog(`Metadata tx ${tx} — waiting for confirmation...`);
      // writeContract returns on tx submission, NOT mining. Wait for receipt
      // so loadToken() reads post-update chain state (otherwise re-read is
      // stale and the cockpit looks like Update Metadata did nothing).
      await publicClient.waitForTransactionReceipt({ hash: tx });
      appendLog(`Metadata confirmed`);
      await loadToken();
    } catch (err) {
      appendLog(`Metadata failed: ${(err as Error).message}`);
    } finally {
      setBusy(false);
    }
  }, [loadToken, notes, owner, tokenId, walletClient]);

  const transferToken = useCallback(async () => {
    if (!/^0x[0-9a-fA-F]{40}$/.test(newOwner)) {
      appendLog('Enter a valid new owner address');
      return;
    }
    const nextData = demoData(tokenId, notes);
    if (!OG_INFT_ADDRESS) {
      setOwner(newOwner as Address);
      setData(nextData);
      persistDemoState(newOwner as Address, nextData);
      appendLog(`Demo transfer token ${tokenId} to ${newOwner}`);
      return;
    }
    setBusy(true);
    try {
      const { client, account } = await walletClient();
      const tx = await client.writeContract({
        account,
        address: OG_INFT_ADDRESS,
        abi: CLAN_AGENT_NFT_ABI,
        functionName: 'iTransfer',
        args: [
          newOwner as Address,
          tokenId,
          nextData,
          {
            newDataHash: hashIntelligentData(nextData),
            encryptedKeyHash: hashText(`dek:${tokenId}:${newOwner}`),
            newUri: `0g://clanworld/clan/${tokenId}/transfer/${Date.now()}`,
            proof: proofHex(`transfer:${tokenId}:${newOwner}`),
          },
        ],
      });
      appendLog(`Transfer tx ${tx} — waiting for confirmation...`);
      // Same as updateMetadata: writeContract returns pre-mining; wait for receipt.
      await publicClient.waitForTransactionReceipt({ hash: tx });
      appendLog(`Transfer confirmed`);
      await loadToken();
    } catch (err) {
      appendLog(`Transfer failed: ${(err as Error).message}`);
    } finally {
      setBusy(false);
    }
  }, [loadToken, newOwner, notes, tokenId, walletClient]);

  return (
    <main
      style={{
        minHeight: '100vh',
        background: '#15120e',
        color: '#f2ead8',
        fontFamily: '"Inter", system-ui, sans-serif',
      }}
    >
      <div style={{ maxWidth: 980, margin: '0 auto', padding: '28px 18px 40px' }}>
        <header style={{ display: 'flex', justifyContent: 'space-between', gap: 16, alignItems: 'end' }}>
          <div>
            <p style={{ margin: '0 0 6px', color: '#d7a84f', fontSize: 12, fontFamily: 'monospace' }}>0G iNFT OWNER CONSOLE</p>
            <h1 style={{ margin: 0, fontSize: 34, lineHeight: 1.05 }}>Clan Elder Transfer</h1>
          </div>
          <button onClick={loadToken} disabled={busy} style={buttonStyle}>
            Load
          </button>
        </header>

        <section style={sectionStyle}>
          <label style={labelStyle}>
            Token / clan ID
            <input value={tokenIdText} onChange={(e) => setTokenIdText(e.target.value)} style={inputStyle} />
          </label>
          <div style={fieldStyle}>
            <span>0G owner</span>
            <strong>{owner}</strong>
          </div>
          <div style={fieldStyle}>
            <span>Data root</span>
            <strong>{currentHash}</strong>
          </div>
        </section>

        <section style={sectionStyle}>
          <label style={{ ...labelStyle, gridColumn: '1 / -1' }}>
            Owner notes
            <textarea
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              rows={5}
              style={{ ...inputStyle, resize: 'vertical', lineHeight: 1.45 }}
            />
          </label>
          <button onClick={updateMetadata} disabled={busy || tokenId === 0n} style={buttonStyle}>
            Update Metadata
          </button>
        </section>

        <section style={sectionStyle}>
          <label style={labelStyle}>
            New owner
            <input value={newOwner} onChange={(e) => setNewOwner(e.target.value)} placeholder="0x..." style={inputStyle} />
          </label>
          <button onClick={transferToken} disabled={busy || tokenId === 0n} style={buttonStyle}>
            Transfer iNFT
          </button>
        </section>

        <section style={sectionStyle}>
          <div style={{ gridColumn: '1 / -1' }}>
            <h2 style={headingStyle}>Intelligent Data</h2>
            {data.map((entry) => (
              <div key={entry.label} style={rowStyle}>
                <span>{entry.label}</span>
                <code>{entry.dataHash}</code>
                <span>{entry.uri}</span>
              </div>
            ))}
          </div>
        </section>

        <section style={sectionStyle}>
          <div style={{ gridColumn: '1 / -1' }}>
            <h2 style={headingStyle}>Demo Log</h2>
            {txLog.length === 0 ? <p style={{ color: '#b9aa8e' }}>No actions yet.</p> : null}
            {txLog.map((line, index) => (
              <div key={`${line}-${index}`} style={{ fontFamily: 'monospace', fontSize: 12, padding: '6px 0', color: '#d7c9ad' }}>
                {line}
              </div>
            ))}
          </div>
        </section>
      </div>
    </main>
  );
}

const sectionStyle: React.CSSProperties = {
  marginTop: 20,
  padding: '18px 0',
  borderTop: '1px solid rgba(242,234,216,0.18)',
  display: 'grid',
  gridTemplateColumns: 'minmax(0, 1fr) auto',
  gap: 16,
  alignItems: 'end',
};

const labelStyle: React.CSSProperties = {
  display: 'grid',
  gap: 8,
  color: '#cbbd9e',
  fontSize: 13,
};

const inputStyle: React.CSSProperties = {
  background: '#241f18',
  color: '#f2ead8',
  border: '1px solid rgba(242,234,216,0.24)',
  borderRadius: 4,
  padding: '11px 12px',
  font: 'inherit',
  minWidth: 0,
};

const buttonStyle: React.CSSProperties = {
  background: '#d7a84f',
  color: '#15120e',
  border: 0,
  borderRadius: 4,
  padding: '12px 16px',
  fontWeight: 700,
  cursor: 'pointer',
};

const fieldStyle: React.CSSProperties = {
  display: 'grid',
  gap: 8,
  minWidth: 0,
  fontSize: 13,
  color: '#cbbd9e',
};

const headingStyle: React.CSSProperties = {
  margin: '0 0 10px',
  fontSize: 18,
};

const rowStyle: React.CSSProperties = {
  display: 'grid',
  gridTemplateColumns: '120px minmax(0, 1fr) minmax(160px, 0.7fr)',
  gap: 12,
  padding: '8px 0',
  borderTop: '1px solid rgba(242,234,216,0.08)',
  fontFamily: 'monospace',
  fontSize: 12,
  overflowWrap: 'anywhere',
};
