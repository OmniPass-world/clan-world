import type { CSSProperties } from 'react'

interface Props {
  color: string
  /** Decorative pattern variant 1-8 */
  variant?: number
  size?: number
  style?: CSSProperties
}

/**
 * Heraldic shield with one of 8 charge variants.
 * Used in the lore page Eight Houses table.
 */
export default function HeraldicShield({ color, variant = 1, size = 64, style }: Props) {
  return (
    <svg
      width={size}
      height={size * 1.2}
      viewBox="0 0 64 78"
      style={style}
      aria-hidden="true"
    >
      {/* Shield body */}
      <path
        d="M 4 6 L 60 6 L 60 38 Q 60 60 32 74 Q 4 60 4 38 Z"
        fill={color}
        stroke="#2A1810"
        strokeWidth="1.5"
        strokeLinejoin="round"
      />
      {/* Shading band */}
      <path
        d="M 4 6 L 60 6 L 60 12 L 4 12 Z"
        fill="#2A1810"
        opacity="0.18"
      />
      {/* Charges by variant */}
      <g fill="#E8D8B5" stroke="#2A1810" strokeWidth="0.7">
        {variant === 1 && (
          // Sword
          <g>
            <rect x="30" y="22" width="4" height="32" />
            <rect x="24" y="22" width="16" height="3" />
            <path d="M 32 54 L 28 60 L 36 60 Z" />
          </g>
        )}
        {variant === 2 && (
          // Wave / ship
          <g>
            <path d="M 16 38 Q 24 32 32 38 Q 40 44 48 38" fill="none" strokeWidth="1.5" />
            <path d="M 16 46 Q 24 40 32 46 Q 40 52 48 46" fill="none" strokeWidth="1.5" />
            <path d="M 22 30 L 42 30 L 38 36 L 26 36 Z" />
            <path d="M 32 22 L 32 30" strokeWidth="1.2" />
            <path d="M 32 22 L 39 28 L 32 28 Z" />
          </g>
        )}
        {variant === 3 && (
          // Sun / coin
          <g>
            <circle cx="32" cy="38" r="9" />
            {Array.from({ length: 8 }).map((_, i) => {
              const a = (i * Math.PI) / 4
              const x1 = 32 + Math.cos(a) * 13
              const y1 = 38 + Math.sin(a) * 13
              const x2 = 32 + Math.cos(a) * 18
              const y2 = 38 + Math.sin(a) * 18
              return <line key={i} x1={x1} y1={y1} x2={x2} y2={y2} strokeWidth="1.2" />
            })}
          </g>
        )}
        {variant === 4 && (
          // Tree
          <g>
            <rect x="30" y="44" width="4" height="14" />
            <path d="M 32 18 L 22 38 L 42 38 Z" />
            <path d="M 32 26 L 24 44 L 40 44 Z" />
          </g>
        )}
        {variant === 5 && (
          // Stars
          <g>
            {[
              { x: 22, y: 28 },
              { x: 42, y: 28 },
              { x: 32, y: 42 },
              { x: 22, y: 56 },
              { x: 42, y: 56 },
            ].map((p, i) => (
              <path
                key={i}
                d={`M ${p.x} ${p.y - 4} L ${p.x + 1} ${p.y - 1} L ${p.x + 4} ${p.y - 1} L ${p.x + 1.5} ${p.y + 1} L ${p.x + 2.5} ${p.y + 4} L ${p.x} ${p.y + 2} L ${p.x - 2.5} ${p.y + 4} L ${p.x - 1.5} ${p.y + 1} L ${p.x - 4} ${p.y - 1} L ${p.x - 1} ${p.y - 1} Z`}
              />
            ))}
          </g>
        )}
        {variant === 6 && (
          // Anvil / hammer
          <g>
            <rect x="20" y="42" width="24" height="6" />
            <rect x="22" y="48" width="20" height="4" />
            <rect x="28" y="22" width="3" height="20" />
            <rect x="22" y="20" width="15" height="6" />
          </g>
        )}
        {variant === 7 && (
          // Tower / monument
          <g>
            <rect x="22" y="50" width="20" height="14" />
            <rect x="24" y="38" width="16" height="12" />
            <rect x="26" y="26" width="12" height="12" />
            <path d="M 26 26 L 32 18 L 38 26 Z" />
          </g>
        )}
        {variant === 8 && (
          // Wolf / fang
          <g>
            <path d="M 18 28 L 32 60 L 46 28 L 38 36 L 32 30 L 26 36 Z" />
          </g>
        )}
      </g>
    </svg>
  )
}
