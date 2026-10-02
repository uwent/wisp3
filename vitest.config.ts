import { fileURLToPath } from 'node:url'
import { svelte } from '@sveltejs/vite-plugin-svelte'
import { defineConfig } from 'vitest/config'

// Separate from vite.config.ts so component tests don't need the Rails/Vite Ruby integration
export default defineConfig({
  plugins: [svelte()],
  resolve: {
    alias: { '@': fileURLToPath(new URL('./app/frontend', import.meta.url)) },
    conditions: ['browser'],
  },
  test: {
    environment: 'jsdom',
    include: ['app/frontend/**/*.test.ts'],
    setupFiles: ['app/frontend/test/setup.ts'],
  },
})
