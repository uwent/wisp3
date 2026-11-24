import { svelte } from '@sveltejs/vite-plugin-svelte'
import inertia from '@inertiajs/vite'
import tailwindcss from '@tailwindcss/vite'
import { defineConfig, type Plugin } from 'vite'
import RubyPlugin from 'vite-plugin-ruby'

// The Svelte inspector loads itself from Vite's client, which MapLibre's worker imports in
// development too, where it fails (no document); this loads it only in a page
const inspectorInPagesOnly: Plugin = {
  name: 'svelte-inspector-in-pages-only',
  enforce: 'post',
  transform(code, id) {
    if (!/vite\/dist\/client\/client\.mjs/.test(id)) return
    return code.replace(
      "import('virtual:svelte-inspector-path:load-inspector.js')",
      "if (typeof document !== 'undefined') import('virtual:svelte-inspector-path:load-inspector.js')",
    )
  },
}

export default defineConfig({
  plugins: [tailwindcss(), RubyPlugin(), inertia(), svelte({ inspector: true }), inspectorInPagesOnly],
  // MapLibre's worker is an ES module (lib/map/maplibre.ts)
  worker: { format: 'es' },
  // Loaded on demand (charts on mount, the map when shown), so the dev server would otherwise only
  // find them on first use, prebundle them and reload the page
  optimizeDeps: {
    include: ['echarts/core', 'echarts/charts', 'echarts/components', 'echarts/renderers', 'maplibre-gl'],
  },
})
