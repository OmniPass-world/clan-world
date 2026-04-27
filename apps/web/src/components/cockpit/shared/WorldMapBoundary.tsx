import { Component, type ReactNode } from 'react';
import { tokens } from '../../../styles/cockpit-tokens';

interface State {
  hasError: boolean;
}

/**
 * Tiny error boundary scoped to the cockpit's center cell. The WorldMap
 * pixi canvas can throw during init when Convex is unreachable / the
 * standalone judge route loads without a backend. In that case we want the
 * 4 mini-cockpits to keep rendering — only the map cell should degrade.
 *
 * Phase B will replace this with a richer "no chain data yet" placeholder
 * once the demo-mode toggle and seeded mock dataset land.
 */
export class WorldMapBoundary extends Component<
  { children: ReactNode },
  State
> {
  override state: State = { hasError: false };

  static getDerivedStateFromError(): State {
    return { hasError: true };
  }

  override componentDidCatch(error: unknown) {
    console.warn('[cockpit] WorldMap failed to mount, rendering fallback:', error);
  }

  override render() {
    if (this.state.hasError) {
      return (
        <div
          data-testid="cockpit-worldmap-fallback"
          style={{
            width: '100%',
            height: '100%',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            background:
              'radial-gradient(ellipse at center, #1a1612 0%, #050505 80%)',
            color: tokens.text.onIron,
            fontFamily: tokens.font.display,
            letterSpacing: '0.2em',
            fontSize: '12px',
            textAlign: 'center',
            padding: tokens.space.xl,
          }}
        >
          <div>
            <div
              style={{
                fontSize: '32px',
                marginBottom: tokens.space.md,
                opacity: 0.6,
              }}
              aria-hidden
            >
              ◈
            </div>
            <div style={{ textTransform: 'uppercase' }}>World Map Offline</div>
            <div
              style={{
                fontFamily: tokens.font.mono,
                fontSize: '10px',
                marginTop: tokens.space.sm,
                color: tokens.text.muted,
                letterSpacing: '0.05em',
              }}
            >
              Standalone view — backend not reachable
            </div>
          </div>
        </div>
      );
    }
    return this.props.children;
  }
}
