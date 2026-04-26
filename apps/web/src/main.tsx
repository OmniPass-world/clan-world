import React from 'react';
import ReactDOM from 'react-dom/client';
import { App } from './App';

// MiniKit + World ID integration TBD — Submission 1 wraps this app as a World mini app.
// We'll initialize @worldcoin/minikit-js at the top of the tree and gate clan-mint
// behind @worldcoin/idkit verification once the World hackathon UX requirements are
// resolved (see docs/reference/sponsor-tech.md).

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
