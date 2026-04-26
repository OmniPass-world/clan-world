import type { CSSProperties } from 'react'

interface Props {
  style?: CSSProperties
  className?: string
}

/**
 * Hand-drawn map of the 8 regions — used in the hero of LandingPage.
 * Stylized as ink-on-parchment: rough strokes, hatched water, calligraphic labels.
 */
export default function RealmMap({ style, className }: Props) {
  return (
    <svg
      viewBox="0 0 800 1000"
      xmlns="http://www.w3.org/2000/svg"
      style={style}
      className={className}
      aria-label="A map of the eight regions of Clan World"
      role="img"
    >
      <defs>
        {/* Parchment-tinted background */}
        <radialGradient id="mapVignette" cx="50%" cy="45%" r="65%">
          <stop offset="0%" stopColor="#E8D8B5" stopOpacity="0" />
          <stop offset="100%" stopColor="#A8956A" stopOpacity="0.45" />
        </radialGradient>

        {/* Hatched-water pattern for sea */}
        <pattern id="hatchSea" width="14" height="14" patternUnits="userSpaceOnUse" patternTransform="rotate(0)">
          <path d="M0 7 Q3 4 6 7 T12 7" stroke="#1F4068" strokeWidth="0.6" fill="none" opacity="0.55" />
          <path d="M0 11 Q3 8 6 11 T12 11" stroke="#1F4068" strokeWidth="0.5" fill="none" opacity="0.4" />
        </pattern>

        {/* Stippled ground for forest */}
        <pattern id="stippleForest" width="10" height="10" patternUnits="userSpaceOnUse">
          <circle cx="2" cy="3" r="0.6" fill="#2A1810" opacity="0.45" />
          <circle cx="7" cy="6" r="0.5" fill="#2A1810" opacity="0.35" />
          <circle cx="4" cy="8" r="0.4" fill="#2A1810" opacity="0.4" />
        </pattern>

        {/* Cross-hatching for mountains */}
        <pattern id="crossMtn" width="8" height="8" patternUnits="userSpaceOnUse" patternTransform="rotate(35)">
          <line x1="0" y1="0" x2="0" y2="8" stroke="#2A1810" strokeWidth="0.5" opacity="0.5" />
        </pattern>

        {/* Wheat dot pattern for farms */}
        <pattern id="wheat" width="12" height="12" patternUnits="userSpaceOnUse">
          <circle cx="3" cy="6" r="0.8" fill="#A87C2F" opacity="0.6" />
          <circle cx="9" cy="3" r="0.7" fill="#A87C2F" opacity="0.55" />
          <circle cx="6" cy="9" r="0.6" fill="#A87C2F" opacity="0.5" />
        </pattern>
      </defs>

      {/* Parchment vignette */}
      <rect x="0" y="0" width="800" height="1000" fill="url(#mapVignette)" />

      {/* ===== Sea / water — fills outside region polygons ===== */}
      <rect x="0" y="0" width="800" height="1000" fill="url(#hatchSea)" opacity="0.55" />

      {/* Compass rose, top-right */}
      <g transform="translate(710, 90)" opacity="0.65">
        <circle r="34" fill="none" stroke="#2A1810" strokeWidth="0.8" />
        <circle r="22" fill="none" stroke="#2A1810" strokeWidth="0.5" />
        <path d="M0,-30 L4,0 L0,30 L-4,0 Z" fill="#9B2A2F" stroke="#2A1810" strokeWidth="0.6" />
        <path d="M-30,0 L0,4 L30,0 L0,-4 Z" fill="#A87C2F" stroke="#2A1810" strokeWidth="0.6" opacity="0.7" />
        <text x="0" y="-38" textAnchor="middle" fontFamily="IM Fell English, serif" fontSize="11" fill="#2A1810">N</text>
        <text x="40" y="3" textAnchor="middle" fontFamily="IM Fell English, serif" fontSize="11" fill="#2A1810">E</text>
        <text x="0" y="48" textAnchor="middle" fontFamily="IM Fell English, serif" fontSize="11" fill="#2A1810">S</text>
        <text x="-40" y="3" textAnchor="middle" fontFamily="IM Fell English, serif" fontSize="11" fill="#2A1810">W</text>
      </g>

      {/* Cartouche title */}
      <g transform="translate(80, 60)">
        <rect x="0" y="0" width="280" height="62" fill="#E8D8B5" stroke="#2A1810" strokeWidth="0.8" />
        <rect x="-4" y="-4" width="288" height="70" fill="none" stroke="#A87C2F" strokeWidth="0.6" />
        <text x="140" y="26" textAnchor="middle" fontFamily="IM Fell English, serif" fontSize="18" fill="#2A1810">
          A Mappe of the
        </text>
        <text x="140" y="48" textAnchor="middle" fontFamily="IM Fell English, serif" fontSize="22" fontStyle="italic" fill="#9B2A2F">
          Eight Regions
        </text>
      </g>

      {/* ============ FOREST (1) — top left ============ */}
      <g>
        <path
          d="M 70 160 Q 105 130 165 145 Q 235 150 295 175 Q 320 220 305 280 Q 290 330 260 345 Q 200 365 145 350 Q 95 335 70 295 Q 60 240 70 160 Z"
          fill="url(#stippleForest)"
          stroke="#2A1810"
          strokeWidth="1.5"
          strokeLinejoin="round"
        />
        {/* trees */}
        <g fill="#3F704D" stroke="#2A1810" strokeWidth="0.6">
          <path d="M120 220 L114 240 L126 240 Z M120 240 L120 252" />
          <path d="M155 195 L148 218 L162 218 Z M155 218 L155 232" />
          <path d="M205 240 L198 263 L212 263 Z M205 263 L205 277" />
          <path d="M245 200 L238 222 L252 222 Z M245 222 L245 236" />
          <path d="M180 290 L173 312 L187 312 Z M180 312 L180 326" />
          <path d="M260 280 L253 302 L267 302 Z M260 302 L260 316" />
          <path d="M105 280 L99 300 L111 300 Z M105 300 L105 313" />
        </g>
        <text x="187" y="210" textAnchor="middle" fontFamily="IM Fell English, serif" fontStyle="italic" fontSize="20" fill="#2A1810">
          Forest
        </text>
      </g>

      {/* ============ MOUNTAINS (2) — top right ============ */}
      <g>
        <path
          d="M 470 145 Q 545 130 615 150 Q 685 165 720 215 Q 740 270 720 325 Q 685 360 620 360 Q 540 365 480 335 Q 450 305 455 260 Q 455 195 470 145 Z"
          fill="url(#crossMtn)"
          stroke="#2A1810"
          strokeWidth="1.5"
          strokeLinejoin="round"
        />
        <g fill="#6B7280" stroke="#2A1810" strokeWidth="0.8" strokeLinejoin="round">
          <path d="M510 280 L545 215 L580 280 Z" fill="#8a8e95" />
          <path d="M540 215 L555 232 L530 232 Z" fill="#E5E7EB" />
          <path d="M585 295 L625 230 L665 295 Z" fill="#7a808a" />
          <path d="M620 230 L635 252 L605 252 Z" fill="#E5E7EB" />
          <path d="M475 305 L500 270 L530 305 Z" fill="#9aa0a8" />
        </g>
        <text x="595" y="200" textAnchor="middle" fontFamily="IM Fell English, serif" fontStyle="italic" fontSize="20" fill="#2A1810">
          Mountains
        </text>
      </g>

      {/* ============ UNICORN TOWN (3) — center ============ */}
      <g>
        <path
          d="M 300 410 Q 390 395 480 410 Q 525 440 510 490 Q 495 530 440 540 Q 365 555 320 530 Q 290 500 295 460 Q 295 430 300 410 Z"
          fill="#D8B4D8"
          fillOpacity="0.55"
          stroke="#2A1810"
          strokeWidth="1.5"
          strokeLinejoin="round"
        />
        {/* sparkles */}
        <g fill="#A87C2F">
          <circle cx="335" cy="430" r="1.2" />
          <circle cx="385" cy="445" r="1" />
          <circle cx="430" cy="425" r="1.4" />
          <circle cx="465" cy="450" r="1" />
          <circle cx="350" cy="475" r="1.1" />
          <circle cx="410" cy="490" r="1.3" />
          <circle cx="445" cy="510" r="0.9" />
        </g>
        {/* spire */}
        <g stroke="#2A1810" strokeWidth="1" fill="#9B2A2F" opacity="0.8">
          <path d="M395 490 L387 460 L382 466 L382 490 Z" />
          <path d="M395 490 L403 460 L408 466 L408 490 Z" fill="#7a1f23" />
          <path d="M387 460 L395 442 L403 460 Z" fill="#A87C2F" />
        </g>
        <text x="395" y="425" textAnchor="middle" fontFamily="IM Fell English, serif" fontStyle="italic" fontSize="19" fill="#7B3F8C">
          Unicorn Town
        </text>
      </g>

      {/* ============ WEST FARMS (4) — left middle ============ */}
      <g>
        <path
          d="M 60 580 Q 120 565 195 575 Q 255 590 270 635 Q 285 680 260 720 Q 220 755 155 745 Q 100 740 70 705 Q 50 660 60 580 Z"
          fill="url(#wheat)"
          stroke="#2A1810"
          strokeWidth="1.5"
          strokeLinejoin="round"
        />
        <rect x="155" y="668" width="22" height="18" fill="#A85A2C" stroke="#2A1810" strokeWidth="0.6" />
        <path d="M155 668 L166 656 L177 668 Z" fill="#7a3f1f" stroke="#2A1810" strokeWidth="0.6" />
        <text x="160" y="615" textAnchor="middle" fontFamily="IM Fell English, serif" fontStyle="italic" fontSize="18" fill="#2A1810">
          West Farms
        </text>
      </g>

      {/* ============ EAST FARMS (5) — right middle ============ */}
      <g>
        <path
          d="M 530 575 Q 605 560 680 580 Q 730 600 740 645 Q 745 695 715 725 Q 670 755 605 745 Q 545 740 525 705 Q 510 660 530 575 Z"
          fill="url(#wheat)"
          stroke="#2A1810"
          strokeWidth="1.5"
          strokeLinejoin="round"
        />
        <rect x="630" y="668" width="22" height="18" fill="#A85A2C" stroke="#2A1810" strokeWidth="0.6" />
        <path d="M630 668 L641 656 L652 668 Z" fill="#7a3f1f" stroke="#2A1810" strokeWidth="0.6" />
        <text x="635" y="615" textAnchor="middle" fontFamily="IM Fell English, serif" fontStyle="italic" fontSize="18" fill="#2A1810">
          East Farms
        </text>
      </g>

      {/* ============ WEST DOCKS (6) — lower left ============ */}
      <g>
        <path
          d="M 90 800 Q 140 790 195 805 Q 245 820 250 855 Q 245 890 220 905 Q 175 915 130 905 Q 90 895 80 870 Q 75 835 90 800 Z"
          fill="#5A8B8B"
          fillOpacity="0.4"
          stroke="#2A1810"
          strokeWidth="1.5"
          strokeLinejoin="round"
        />
        {/* dock pilings */}
        <g stroke="#2A1810" strokeWidth="1" fill="#5A3D28">
          <rect x="135" y="855" width="3" height="14" />
          <rect x="155" y="852" width="3" height="14" />
          <rect x="175" y="855" width="3" height="14" />
          <rect x="195" y="853" width="3" height="14" />
          <line x1="130" y1="852" x2="200" y2="852" strokeWidth="1.2" />
        </g>
        <text x="167" y="835" textAnchor="middle" fontFamily="IM Fell English, serif" fontStyle="italic" fontSize="17" fill="#2A1810">
          West Docks
        </text>
      </g>

      {/* ============ EAST DOCKS (7) — lower right ============ */}
      <g>
        <path
          d="M 555 800 Q 615 790 670 805 Q 720 820 720 855 Q 715 895 690 905 Q 645 915 600 905 Q 560 895 550 870 Q 545 835 555 800 Z"
          fill="#4F7E7E"
          fillOpacity="0.4"
          stroke="#2A1810"
          strokeWidth="1.5"
          strokeLinejoin="round"
        />
        <g stroke="#2A1810" strokeWidth="1" fill="#5A3D28">
          <rect x="600" y="855" width="3" height="14" />
          <rect x="620" y="852" width="3" height="14" />
          <rect x="640" y="855" width="3" height="14" />
          <rect x="660" y="853" width="3" height="14" />
          <line x1="595" y1="852" x2="665" y2="852" strokeWidth="1.2" />
        </g>
        <text x="632" y="835" textAnchor="middle" fontFamily="IM Fell English, serif" fontStyle="italic" fontSize="17" fill="#2A1810">
          East Docks
        </text>
      </g>

      {/* ============ DEEP SEA (8) — bottom ============ */}
      <g>
        <path
          d="M 280 920 Q 380 905 480 920 Q 545 935 530 970 Q 480 985 400 980 Q 320 980 290 970 Q 270 945 280 920 Z"
          fill="#2C3E5D"
          fillOpacity="0.6"
          stroke="#2A1810"
          strokeWidth="1.5"
          strokeLinejoin="round"
        />
        {/* sea monster */}
        <g stroke="#2A1810" strokeWidth="0.8" fill="none" opacity="0.85">
          <path d="M325 950 Q335 940 345 950 Q355 960 365 950 Q375 940 385 950" />
          <path d="M395 955 Q405 947 412 955" />
          <circle cx="333" cy="947" r="0.7" fill="#2A1810" />
        </g>
        <text x="405" y="935" textAnchor="middle" fontFamily="IM Fell English, serif" fontStyle="italic" fontSize="17" fill="#E8D8B5">
          Deep Sea
        </text>
        <text x="430" y="975" textAnchor="middle" fontFamily="IM Fell English, serif" fontSize="9" fontStyle="italic" fill="#E8D8B5" opacity="0.7">
          here be drakes
        </text>
      </g>

      {/* Travel routes — faded dotted lines */}
      <g stroke="#2A1810" strokeWidth="0.8" strokeDasharray="3,3" fill="none" opacity="0.35">
        <path d="M210 290 Q 280 360 360 410" />
        <path d="M580 290 Q 510 360 440 410" />
        <path d="M390 540 Q 380 580 230 600" />
        <path d="M410 540 Q 425 580 580 600" />
        <path d="M180 720 Q 175 760 165 800" />
        <path d="M620 720 Q 625 760 635 800" />
        <path d="M210 880 Q 290 910 380 925" />
        <path d="M600 880 Q 520 910 430 925" />
      </g>

      {/* Subtle ink-spatter ageing flecks */}
      <g fill="#2A1810" opacity="0.18">
        <circle cx="60" cy="450" r="0.6" />
        <circle cx="120" cy="500" r="0.4" />
        <circle cx="380" cy="60" r="0.5" />
        <circle cx="725" cy="450" r="0.5" />
        <circle cx="700" cy="780" r="0.6" />
        <circle cx="50" cy="650" r="0.4" />
      </g>
    </svg>
  )
}
