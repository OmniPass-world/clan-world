import { Component, type ReactNode } from 'react';
import { tokens } from '../../../styles/cockpit-tokens';

interface State {
  hasError: boolean;
  errorMessage?: string;
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

  static getDerivedStateFromError(error: unknown): State {
    const errorMessage =
      error instanceof Error ? error.message : String(error ?? 'unknown');
    return { hasError: true, errorMessage };
  }

  override componentDidCatch(error: unknown, info: unknown) {
    // Use console.error (not warn) so the boundary trip is loud in DevTools
    // and surfaces in error-tracking integrations. Includes React component
    // stack so we can see WHERE in the WorldMap tree the throw came from.
    console.error('[cockpit] WorldMap failed to mount:', error, info);
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
              {this.state.errorMessage
                ? `error: ${this.state.errorMessage}`
                : 'Standalone view — backend not reachable'}
            </div>
          </div>
        </div>
      );
    }
    return this.props.children;
  }
}
