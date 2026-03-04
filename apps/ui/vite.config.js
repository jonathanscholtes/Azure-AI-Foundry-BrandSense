import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      '/validate': { target: 'http://localhost:80', changeOrigin: true },
      '/tools':    { target: 'http://localhost:80', changeOrigin: true },
      '/health':   { target: 'http://localhost:80', changeOrigin: true },
    },
  },
  build: {
    outDir: 'dist',
    emptyOutDir: true,
  },
})
