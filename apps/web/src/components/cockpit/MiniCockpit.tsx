import { useState } from 'react';
import { tokens, type ElderDef } from '../../styles/cockpit-tokens';
import { CockpitTabBar, type TabId } from './shared/CockpitTabBar';
import { TerminalTab } from './tabs/TerminalTab';
import { VaultTab } from './tabs/VaultTab';
import { ClansmanTab } from './tabs/ClansmanTab';
import { ZeroGTab } from './tabs/ZeroGTab';
import { CommsTab } from './tabs/CommsTab';

interface Props {
  elder: ElderDef;
  /** Stub tick counter — Phase B will source this from the engine. */
  tick?: number;
  tickMax?: number;
}

/**
 * One corner panel — tab bar on top, content below. Default tab is Terminal
 * per Liam's spec ("First tab is terminal").
 */
export function MiniCockpit({ elder, tick = 4, tickMax = 10 }: Props) {
  const [active, setActive] = useState<TabId>('terminal');
  const testIdPrefix = `mini-cockpit-${elder.clanId}`;

  return (
    <section
      data-testid={testIdPrefix}
      data-clan-id={elder.clanId}
      style={{
        display: 'flex',
        flexDirection: 'column',
        background: tokens.bg.iron,
        border: `1px solid ${tokens.border.iron}`,
        borderTop: `2px solid ${elder.accent}`,
        boxShadow: tokens.shadow.panel,
        borderRadius: tokens.radius.md,
        overflow: 'hidden',
        minWidth: 0,
        minHeight: 0,
      }}
      aria-label={`Mini cockpit for ${elder.name}`}
    >
      <CockpitTabBar
        active={active}
        onSelect={setActive}
        tick={tick}
        tickMax={tickMax}
        clanName={elder.name}
        clanAccent={elder.accent}
        clanGlyph={elder.glyph}
        testIdPrefix={testIdPrefix}
      />
      <div
        style={{
          flex: 1,
          display: 'flex',
          flexDirection: 'column',
          minHeight: 0,
          overflow: 'hidden',
        }}
      >
        {active === 'terminal' && <TerminalTab elder={elder} testIdPrefix={testIdPrefix} />}
        {active === 'vault'    && <VaultTab    elder={elder} testIdPrefix={testIdPrefix} />}
        {active === 'clansman' && <ClansmanTab elder={elder} testIdPrefix={testIdPrefix} />}
        {active === '0g'       && <ZeroGTab    elder={elder} testIdPrefix={testIdPrefix} />}
        {active === 'comms'    && <CommsTab    elder={elder} testIdPrefix={testIdPrefix} />}
      </div>
    </section>
  );
}
