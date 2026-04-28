import { tokens } from '../../../styles/cockpit-tokens';
import type { ElderDef } from '../../../styles/cockpit-tokens';

interface Props {
  elder: ElderDef;
  testIdPrefix: string;
}

/**
 * Terminal tab — live ttyd iframe pointing at this Elder's tmux mirror.
 *
 * The iframe loads `https://cockpit.clan-world.com/elder-{N}-tty/`, which is
 * served by Caddy in front of `ttyd-elder-{N}.service`. ttyd renders the
 * Elder's tmux session as a read-only WebSocket-fed terminal in the browser.
 *
 * If the upstream service is down, the iframe will show the browser's
 * default connection-refused chrome — the global ConnectionPill in the
 * cockpit header is responsible for surfacing connection state to the user.
 *
 * `sandbox="allow-scripts allow-same-origin"` is required because ttyd
 * upgrades to a WebSocket on the same origin; stripping `allow-same-origin`
 * breaks the WS handshake.
 */
export function TerminalTab({ elder, testIdPrefix }: Props) {
  const url = `https://cockpit.clan-world.com/elder-${elder.clanId}-tty/`;

  return (
    <div
      data-testid={`${testIdPrefix}-content-terminal`}
      style={{
        flex: 1,
        display: 'flex',
        flexDirection: 'column',
        background: '#000',
        minHeight: 0,
      }}
    >
      <div
        style={{
          color: tokens.text.onIronDim,
          fontSize: '9px',
          letterSpacing: '0.15em',
          padding: `4px ${tokens.space.md}`,
          textTransform: 'uppercase',
          fontFamily: tokens.font.mono,
          background: tokens.bg.ironDeep,
          borderBottom: `1px solid ${tokens.border.iron}`,
          flexShrink: 0,
        }}
      >
        ── Elder-{elder.clanId} tmux mirror (read-only) ──
      </div>
      <iframe
        src={url}
        title={`Elder ${elder.clanId} tmux mirror`}
        className="cockpit-terminal-iframe"
        sandbox="allow-scripts allow-same-origin"
        style={{
          flex: 1,
          width: '100%',
          border: 'none',
          background: '#000',
        }}
      />
    </div>
  );
}
