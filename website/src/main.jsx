import './vibedit-responsive.css';
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import App from './App.jsx';
import './styles.css';

// Umami heatmaps. Unlike script.js, recorder.js ignores data-domains and the
// `umami.disabled` opt-out, so it is only loaded on the live site, never from dev.
function loadRecorder() {
  if (location.hostname !== 'getfifteen.de') return;
  try {
    if (localStorage.getItem('umami.disabled')) return;
  } catch {
    // storage blocked: fall through and record as usual
  }
  const s = document.createElement('script');
  s.defer = true;
  s.src = 'https://umami.mirzapolat.com/recorder.js';
  s.dataset.websiteId = '143a8cd7-51b4-48e5-8b1f-296b2c448a7b';
  document.head.appendChild(s);
}
loadRecorder();

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
