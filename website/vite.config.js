import { vibedit } from '@vibedit/vite';
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react(), vibedit()],
  server: {
    // In dev, `npm start` (after a build) answers /download and /api on :3000.
    proxy: {
      '/api': 'http://localhost:3000',
      '/download': 'http://localhost:3000',
    },
  },
});
