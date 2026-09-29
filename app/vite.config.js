import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// The built site goes to ../dist at the repo root — cPanel publishes that folder.
export default defineConfig({
  plugins: [react()],
  base: '/',
  // snarkjs and its ffjavascript dependency were written for Node and still reach for
  // `global`. Browsers call it `globalThis`. Without this line the proving code loads and
  // then dies on the first reference, which reads as a mysterious blank panel rather than
  // a missing polyfill.
  define: { global: 'globalThis' },
  build: {
    outDir: '../dist',
    emptyOutDir: true,
    // snarkjs is ~1.4 MB and only module 16 needs it, so it is imported dynamically and
    // lands in its own chunk. Raising the warning limit here would hide that; leaving it
    // alone means the build tells us if it ever creeps into the main bundle.
  },
  server: {
    // allow importing ../deployments/*.json during dev
    fs: { allow: ['..'] },
  },
});
