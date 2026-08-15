import { createRoot } from 'react-dom/client';
import './index.css';
import ServiceModeRoot from './components/ServiceModeRoot';

createRoot(document.getElementById('root')!).render(<ServiceModeRoot />);

// Register service worker for PWA
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/sw.js').catch(() => {});
  });
}
