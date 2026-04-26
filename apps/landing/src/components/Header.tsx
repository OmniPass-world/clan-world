import { Link } from 'react-router-dom'
import { GITHUB_URL } from '../constants'

const REPO_LINK = GITHUB_URL

export default function Header() {
  return (
    <header className="site-header">
      <div className="site-header-inner">
        <Link to="/" className="site-brand" aria-label="Clan World home">
          <svg className="site-brand-mark" viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg">
            <path d="M16 2 L28 8 L28 18 C28 24 22 28 16 30 C10 28 4 24 4 18 L4 8 Z"
              stroke="currentColor" strokeWidth="1.5" fill="rgba(168,124,47,0.12)" />
            <path d="M16 9 L20 16 L16 23 L12 16 Z" fill="currentColor" />
            <circle cx="16" cy="16" r="1.5" fill="var(--parchment)" />
          </svg>
          <span>Clan World <i style={{ color: 'var(--vermillion)' }}>: Ælder Whispers</i></span>
        </Link>
        <nav className="site-nav">
          <Link to="/lore" className="desktop-only">The Chronicle</Link>
          <a href={REPO_LINK} target="_blank" rel="noopener noreferrer" className="pixel-link" aria-label="GitHub repository">
            ▲ GITHUB
          </a>
          <a href="https://app.clan-world.com" className="cta-secondary">
            Enter Realm
          </a>
        </nav>
      </div>
    </header>
  )
}
