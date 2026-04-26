import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { BrowserRouter, Routes, Route } from 'react-router-dom'
import './styles/global.css'
import LandingPage from './pages/LandingPage'
import LorePage from './pages/LorePage'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<LandingPage />} />
        <Route path="/lore" element={<LorePage />} />
      </Routes>
    </BrowserRouter>
  </StrictMode>,
)
