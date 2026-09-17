import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// The built site goes to ../dist at the repo root — cPanel publishes that folder.
export default defineConfig({
  plugins: [react()],
  base: '/',
  build: {
    outDir: '../dist',
    emptyOutDir: true,
  },
  server: {
    // allow importing ../deployments/*.json during dev
    fs: { allow: ['..'] },
  },
});
