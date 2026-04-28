import { Link } from 'react-router-dom'
import { APP_URL, GITHUB_URL } from '../constants'

export default function Footer() {
  return (
    <footer className="site-footer">
      <div className="site-footer-inner">
        <div className="site-footer-grid">
          <div>
            <h4>Clan World <i>: Ælder Whispers</i></h4>
            <p style={{ color: 'var(--ink-soft)', fontSize: '0.95rem', maxWidth: '24rem' }}>
              An onchain realm of autonomous Elders, illuminated against parchment for those bold
              enough to read it. A hackathon submission to <em>OpenAgents Track 2</em> and the
              <em> World mini app</em> challenge — among others.
            </p>
            <p style={{ marginTop: '1rem' }} className="pixel">
              ⌬ Built on Base · 0G
            </p>
          </div>

          <div>
            <h4>Realm</h4>
            <ul>
              <li><a href={APP_URL}>Enter the realm</a></li>
              <li><Link to="/">Landing folio</Link></li>
              <li><Link to="/lore">The chronicle</Link></li>
            </ul>
          </div>

          <div>
            <h4>The Codex</h4>
            <ul>
              <li><a href={GITHUB_URL} target="_blank" rel="noopener noreferrer">GitHub repository</a></li>
              <li><a href={`${GITHUB_URL}/tree/main/images`} target="_blank" rel="noopener noreferrer">Image archive</a></li>
              <li><a href="https://docs.0g.ai/developer-hub/building-on-0g/inft/erc7857" target="_blank" rel="noopener noreferrer">ERC-7857 spec</a></li>
            </ul>
          </div>

          <div>
            <h4>Powers</h4>
            <ul>
              <li><a href="https://uniswap.org" target="_blank" rel="noopener noreferrer">Uniswap</a></li>
              <li><a href="https://0g.ai" target="_blank" rel="noopener noreferrer">0G Labs</a></li>
              <li><a href="https://base.org" target="_blank" rel="noopener noreferrer">Base</a></li>
              <li><a href="https://world.org" target="_blank" rel="noopener noreferrer">World</a></li>
              <li><a href="https://gensyn.ai" target="_blank" rel="noopener noreferrer">Gensyn</a></li>
            </ul>
          </div>
        </div>

        <div className="colophon">
          <em>
            ✦ Inscribed in the year of our agents 2026 · forged in pen and pixel · 
            offered freely to scholars of emergent behaviour ✦
          </em>
        </div>
      </div>
    </footer>
  )
}
