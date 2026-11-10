import { svelte } from '@sveltejs/vite-plugin-svelte'
import inertia from '@inertiajs/vite'
import tailwindcss from '@tailwindcss/vite'
import { defineConfig } from 'vite'
import RubyPlugin from 'vite-plugin-ruby'

export default defineConfig({
  plugins: [tailwindcss(), RubyPlugin(), inertia(), svelte()],
  // MapLibre's worker is an ES module (lib/map/maplibre.ts)
  worker: { format: 'es' },
  // Loaded on demand (charts on mount, the map when shown), so the dev server would otherwise only
  // find them on first use, prebundle them and reload the page
  optimizeDeps: {
    include: ['echarts/core', 'echarts/charts', 'echarts/components', 'echarts/renderers', 'maplibre-gl'],
  },
})
