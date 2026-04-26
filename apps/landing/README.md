# Clan World: Ælder Whispers — Landing & Chronicle

Marketing site for the hackathon submission, themed as an illuminated
manuscript. Two pages:

- **`/`** — landing folio: hero map, premise, demo hook, codex of powers
  (sponsor tech), tales of emergent behaviour, path to the chronicle
- **`/lore`** — the chronicle: lore (4 chapters) + game rules (9 sections),
  combined as a single long scroll

## Running locally

```bash
cd clanworld-landing
npm install
npm run dev
```

Production build:

```bash
npm run build
npm run preview
```

## Stack

- Vite + React 19 + TypeScript
- React Router (`/` and `/lore`)
- Plain CSS with custom properties — no Tailwind, no UI libraries
- Custom inline-SVG illustrations for the map, heraldic shields, diagrams,
  charts, and ornaments
- `motion` is installed but not currently wired in — the reveal animations
  use a small IntersectionObserver hook (`src/hooks/useReveal.ts`) to keep
  bundle size honest

## Theme

- **Aesthetic:** illuminated manuscript meets 16-bit JRPG overworld
- **Palette:** parchment, ink, vermillion, gold leaf, lapis (CSS variables
  in `src/styles/global.css`)
- **Typography:** IM Fell English (display), EB Garamond (body), VT323
  (pixel margin annotations) — all from Google Fonts
- **Sponsor logos** are loaded from official URLs; if any fail
  (cross-origin, etc.) the SponsorCard component falls back to a
  text-initials wax-seal automatically

## Customising

### Sponsor data

`src/data/sponsors.ts` — edit the eight `POWERS` entries to change names,
copy, links, or logo URLs. Logos can be set to `null` to use the text
fallback explicitly.

### Houses / lore content

`src/pages/LorePage.tsx` — `HOUSES` and `BANDIT_TIERS` arrays are at the
top of the file. Yield/travel/market tables are inline JSX in their
respective chapters.

### Repo / app links

`src/constants.ts` — `APP_URL` and `GITHUB_URL`.

### Custom artwork

The repo's image folder at `https://github.com/OmniPass-world/clan-world/tree/main/images`
isn't currently referenced; the page uses inline SVG illustrations so it
works standalone. If you want to swap in repo images, the easiest places:

- **Hero map** — replace `<RealmMap />` in `LandingPage.tsx` with an
  `<img>` pointing at a raw GitHub URL
- **Tale cards** — add an `<img>` element inside each `tale-frame`
- **Sponsor wax seals** — already pulling official logos via URL; can be
  swapped to repo images by editing `logoUrl` in `sponsors.ts`

## Routes

```
/        →  LandingPage
/lore    →  LorePage  (lore + rules combined)
```

For SPA hosting, configure your host to serve `index.html` for unknown
routes (Vercel does this automatically; on Netlify add a `_redirects`
file with `/* /index.html 200`).

## Deploy target

CTA buttons link to `https://app.clan-world.com`. Repository at
`https://github.com/OmniPass-world/clan-world`.
