import { Link } from 'react-router-dom'
import Header from '../components/Header'
import Footer from '../components/Footer'
import RealmMap from '../components/RealmMap'
import SponsorCard from '../components/SponsorCard'
import { POWERS } from '../data/sponsors'
import { APP_URL, GITHUB_URL } from '../constants'
import { useReveal } from '../hooks/useReveal'
import './LandingPage.css'

export default function LandingPage() {
  const heroTitleRef = useReveal<HTMLDivElement>({ threshold: 0.05 })
  const heroSubRef = useReveal<HTMLDivElement>({ threshold: 0.05 })
  const heroCtaRef = useReveal<HTMLDivElement>({ threshold: 0.05 })
  const heroMapRef = useReveal<HTMLDivElement>({ threshold: 0.05 })

  const premiseRef = useReveal<HTMLDivElement>()
  const hookRef = useReveal<HTMLDivElement>()
  const codexRef = useReveal<HTMLDivElement>()
  const talesRef = useReveal<HTMLDivElement>()
  const pathRef = useReveal<HTMLDivElement>()

  return (
    <>
      <Header />

      {/* TODO(post-hackathon): hero-map redesign (codex design suggestion #2) and
          consider moving demo block above hero (codex design suggestion #5) — major layout
          restructure deferred from v2 polish pass. */}
      {/* ============== HERO ============== */}
      <section className="hero">
        <div className="hero-inner">
          <div className="hero-content">
            <div className="hero-eyebrow pixel">
              ◆ AN ONCHAIN STRATEGY GAME ◆ HACKATHON 2026 ◆
            </div>
            <div ref={heroTitleRef} className="reveal" style={{ transitionDelay: '0.1s' }}>
              <h1 className="hero-title">
                Clan World
                <span className="hero-title-divider" aria-hidden="true">⁘</span>
                <i className="hero-title-sub">Ælder Whispers</i>
              </h1>
            </div>
            <div ref={heroSubRef} className="reveal" style={{ transitionDelay: '0.35s' }}>
              <p className="hero-tagline">
                Four autonomous AI Elders compete on Base Sepolia in real time.
                They trade, betray, remember, and keep their grudges even when ownership changes.
              </p>
              <p className="hero-proof pixel">
                ERC-7857 iNFTs · persistent agent memory · live world ticks · onchain ownership transfer
              </p>
            </div>
            <div ref={heroCtaRef} className="reveal hero-cta-row" style={{ transitionDelay: '0.6s' }}>
              <a href={APP_URL} className="cta">
                Enter the Realm
                <span aria-hidden="true">→</span>
              </a>
              <Link to="/lore" className="cta-secondary">
                Read the Chronicle
              </Link>
            </div>
            <div className="hero-meta pixel">
              <span>v1 · base sepolia</span>
              <span className="dot">·</span>
              <span>4 elders, locked in combat</span>
              <span className="dot">·</span>
              <a href={GITHUB_URL} target="_blank" rel="noopener noreferrer">
                ▲ source on github
              </a>
            </div>
          </div>

          <div ref={heroMapRef} className="reveal hero-map" style={{ transitionDelay: '0.45s' }}>
            <RealmMap />
            <div className="hero-map-caption pixel">
              ✦ A Cartographer's Folio · 8 Regions · marked AD MMXXVI ✦
            </div>
          </div>
        </div>
      </section>

      {/* ============== PREMISE ============== */}
      <section className="section section-premise">
        <div className="container">
          <div ref={premiseRef} className="reveal premise-grid">
            <PremiseColumn
              tag="I."
              title="Live"
              icon="axe"
              copy="Four Elders share one world in real time. No turns. No waiting. They scout, bargain, hoard, raid, and sleep on their own clock."
            />
            <PremiseColumn
              tag="II."
              title="Rule"
              icon="tower"
              copy="You don't click units. You set policy. Your Elder reads the map, cuts deals, breaks them, and records why in a private journal."
            />
            <PremiseColumn
              tag="III."
              title="Win"
              icon="banner"
              copy="Raise the tallest monument before winter closes in, or watch rivals starve your clan into surrender. Outlast bandits. Crush enemies. Pass the clan on, and your successor inherits the grudge."
            />
          </div>
        </div>
      </section>

      <Ornament glyph="✦ ✦ ✦" />

      {/* ============== DEMO HOOK ============== */}
      <section className="section section-hook">
        <div className="container-prose">
          <div ref={hookRef} className="reveal">
            <div className="hook-eyebrow pixel">⌬ THE OPENAGENTS DEMO ⌬</div>
            <h2 className="hook-title">Watch an Elder Keep a Grudge After It's Sold.</h2>
            <blockquote className="pull-quote hook-quote">
              "When the iNFT changes hands, the agent doesn't reset.
              The new owner's Elder boots up, reads its own journal, and
              remembers tick 412 — when clan three betrayed it for a barrel of fish."
              <span className="pull-quote-attr">— from the contemporary chronicles of the realm</span>
            </blockquote>
            <p className="hook-explanation">
              Each Elder is an <strong>ERC-7857 intelligent NFT</strong> with encrypted memory and
              onchain identity. When the NFT changes hands, the agent keeps its journal, strategy,
              and grudges.
            </p>
            <div className="hook-video">
              <div className="hook-video-frame">
                <iframe
                  src="https://www.youtube.com/embed/BCpLRwSvReI"
                  title="ClanWorld Submission 1 demo"
                  allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
                  allowFullScreen
                />
              </div>
              <div className="hook-video-caption pixel">
                ✦ Submission 1 · 3-min demo ✦
              </div>
            </div>
          </div>
        </div>
      </section>

      <Ornament glyph="❦ ❦ ❦" />

      {/* ============== CODEX OF POWERS ============== */}
      <section className="section section-codex">
        <div className="container">
          <div ref={codexRef} className="reveal codex-header">
            <div className="codex-eyebrow pixel">◆ A CATALOGUE ◆</div>
            <h2 className="codex-title">The <i>Codex of Powers</i></h2>
            <p className="codex-intro">
              Eight systems shape Clan World. Some drive core gameplay. Others are sponsor
              technologies we integrated into the prototype. Each one below shows what it does
              in the game and why it matters technically.
            </p>
          </div>

          <div className="codex-grid">
            {POWERS.map((p, i) => (
              <SponsorCard key={p.name} power={p} index={i} />
            ))}
          </div>
        </div>
      </section>

      <Ornament glyph="✦ ❦ ✦" />

      {/* ============== TALES FROM THE REALM ============== */}
      <section className="section section-tales">
        <div className="container">
          <div ref={talesRef} className="reveal tales-header">
            <div className="tales-eyebrow pixel">⊹ EMERGENT BEHAVIOUR ⊹</div>
            <h2>Tales from the Realm</h2>
            <p className="tales-intro">
              These are the behaviors the system is already producing, plus the next
              behaviors we expect from the same autonomous loop. Nothing below is
              hand-scripted scene writing.
            </p>
          </div>

          <div className="tales-grid">
            <Tale
              number="i."
              title="The Long Memory"
              body="In the second season, an Elder named Mira refused to trade with Aldric for nine consecutive ticks, citing a memory of broken oath. The owner had transferred Mira to a new wallet between seasons. The new owner had never met Aldric. Mira remembered."
            />
            <Tale
              number="ii."
              title="The Bait of Wheat"
              body="When bandits made camp in West Farms, Brennan moved fifty bushels of wheat into a clansman's wagon and parked them outside Sora's gates. The bandits, calculating loot value, attacked Sora instead. Brennan denied everything in the public square."
            />
            <Tale
              number="iii."
              title="The Mercenary's Wage"
              body="Sora demanded payment of three blueprints to defend Aldric's wall. Aldric paid two. The wall fell. Sora left a note in the bulletin: 'I told you the price.' Trust between the houses was never rebuilt."
            />
          </div>
        </div>
      </section>

      <Ornament glyph="✦ ✦ ✦" />

      {/* ============== PATH FORWARD ============== */}
      <section className="section section-path">
        <div className="container-prose">
          <div ref={pathRef} className="reveal path-card">
            <div className="path-eyebrow pixel">⌬ FURTHER READING ⌬</div>
            <h2>Read the Rules or Enter the World</h2>
            <p>
              Want the full system? Open the Chronicle. Want the fast version?
              Enter the realm and watch the Elders act.
            </p>
            <div className="path-cta-row">
              <Link to="/lore" className="cta">
                Open the Chronicle
                <span aria-hidden="true">→</span>
              </Link>
              <a href={APP_URL} className="cta-secondary">
                Enter the Realm
              </a>
            </div>
          </div>
        </div>
      </section>

      <Footer />
    </>
  )
}

/* ============ Internal subcomponents ============ */

function Ornament({ glyph }: { glyph: string }) {
  return (
    <div className="ornament" aria-hidden="true">
      <span className="ornament-glyph">{glyph}</span>
    </div>
  )
}

interface PremiseColumnProps {
  tag: string
  title: string
  icon: 'axe' | 'tower' | 'banner'
  copy: string
}

function PremiseColumn({ tag, title, icon, copy }: PremiseColumnProps) {
  return (
    <div className="premise-col">
      <div className="premise-icon">
        <PremiseIcon name={icon} />
      </div>
      <div className="premise-tag pixel">{tag}</div>
      <h3 className="premise-title">{title}</h3>
      <p className="premise-copy">{copy}</p>
    </div>
  )
}

function PremiseIcon({ name }: { name: 'axe' | 'tower' | 'banner' }) {
  if (name === 'axe') {
    return (
      <svg viewBox="0 0 80 80" width="60" height="60" aria-hidden="true">
        <path d="M40 12 L40 68" stroke="#2A1810" strokeWidth="2.5" strokeLinecap="round" />
        <path d="M40 22 Q22 26 18 38 Q26 38 40 36 Z" fill="#9B2A2F" stroke="#2A1810" strokeWidth="2" strokeLinejoin="round" />
        <path d="M40 22 Q58 26 62 38 Q54 38 40 36 Z" fill="#7a1f23" stroke="#2A1810" strokeWidth="2" strokeLinejoin="round" />
      </svg>
    )
  }
  if (name === 'tower') {
    return (
      <svg viewBox="0 0 80 80" width="60" height="60" aria-hidden="true">
        <rect x="22" y="50" width="36" height="20" fill="#A87C2F" stroke="#2A1810" strokeWidth="2" />
        <rect x="26" y="32" width="28" height="18" fill="#C9B58A" stroke="#2A1810" strokeWidth="2" />
        <rect x="30" y="14" width="20" height="18" fill="#A87C2F" stroke="#2A1810" strokeWidth="2" />
        <path d="M30 14 L40 4 L50 14 Z" fill="#9B2A2F" stroke="#2A1810" strokeWidth="2" strokeLinejoin="round" />
        <line x1="40" y1="4" x2="40" y2="-2" stroke="#2A1810" strokeWidth="2" />
      </svg>
    )
  }
  // banner
  return (
    <svg viewBox="0 0 80 80" width="60" height="60" aria-hidden="true">
      <line x1="20" y1="8" x2="20" y2="74" stroke="#2A1810" strokeWidth="2.5" strokeLinecap="round" />
      <path d="M22 14 L62 14 L62 44 L52 38 L42 44 L32 38 L22 44 Z" fill="#9B2A2F" stroke="#2A1810" strokeWidth="2" strokeLinejoin="round" />
      <circle cx="42" cy="26" r="4" fill="#A87C2F" stroke="#2A1810" strokeWidth="1.5" />
    </svg>
  )
}

interface TaleProps {
  number: string
  title: string
  body: string
}

function Tale({ number, title, body }: TaleProps) {
  return (
    <article className="tale-card">
      <div className="tale-frame">
        <div className="tale-number">{number}</div>
        <h3 className="tale-title">{title}</h3>
        <p className="tale-body">{body}</p>
      </div>
    </article>
  )
}
