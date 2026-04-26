import type { SponsorPower } from '../data/sponsors'
import './SponsorCard.css'

interface Props {
  power: SponsorPower
  index: number
}

export default function SponsorCard({ power, index }: Props) {
  return (
    <a
      href={power.href}
      target="_blank"
      rel="noopener noreferrer"
      className="sponsor-card"
      style={{ ['--reveal-delay' as string]: `${index * 80}ms` }}
    >
      <div className="sponsor-card-frame">
        <div className="sponsor-card-seal">
          {power.logoUrl ? (
            <img
              src={power.logoUrl}
              alt={power.logoAlt}
              className="sponsor-card-logo"
              loading="lazy"
              onError={(e) => {
                // graceful fallback to lore-name initials
                const target = e.currentTarget
                const initials = power.name
                  .split(/\s+/)
                  .map((w) => w[0])
                  .slice(0, 2)
                  .join('')
                  .toUpperCase()
                target.style.display = 'none'
                const fallback = target.parentElement?.querySelector('.sponsor-card-fallback')
                if (fallback instanceof HTMLElement) {
                  fallback.style.display = 'flex'
                  fallback.textContent = initials
                }
              }}
            />
          ) : null}
          <span
            className="sponsor-card-fallback"
            style={{ display: power.logoUrl ? 'none' : 'flex' }}
            aria-hidden={!!power.logoUrl}
          >
            {power.name
              .split(/\s+/)
              .map((w) => w[0])
              .slice(0, 2)
              .join('')
              .toUpperCase()}
          </span>
        </div>

        <div className="sponsor-card-body">
          <div className="sponsor-card-margin pixel">{power.marginNote}</div>
          <div className="sponsor-card-name">{power.name}</div>
          <div className="sponsor-card-lorename">{power.loreName}</div>
          <p className="sponsor-card-lore">{power.loreDesc}</p>
          <p className="sponsor-card-tech">{power.techDesc}</p>
        </div>
      </div>
    </a>
  )
}
