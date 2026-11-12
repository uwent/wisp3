<script lang="ts">
  import 'maplibre-gl/dist/maplibre-gl.css'

  import { onMount, untrack } from 'svelte'
  import type { GeoJSONSource, Map as MapLibreMap } from 'maplibre-gl'

  import { GEOCODER_ATTRIBUTION } from '@/lib/geocode'
  import { type Boundary, boundaryBounds, boundaryCenter, type LngLat } from '@/lib/geo'
  import { basemapStyle, type Basemap, LABEL_FONT, setBasemap } from '@/lib/map/basemaps'
  import BasemapToggle from '@/lib/map/BasemapToggle.svelte'
  import { loadMapLibre } from '@/lib/map/maplibre'

  import { addReferenceLayers, type Reference } from './references'

  export type ShapeOnMap = { boundary: Boundary; label: string; state: 'skip' | 'field' | 'new' }

  // The shapes from an outline file (PLAN.md Phase 8 G.10), numbered as in the list below the map
  // and colored by where each goes (an existing field, a new one, or skipped), over the operation's
  // systems and outlined fields. Clicking a shape picks its row.
  let {
    shapes,
    references,
    selected = null,
    onselect,
    fileKey = 0,
    height = '28rem',
  }: {
    shapes: ShapeOnMap[]
    /** Changes with each file read, to fit the map to its shapes */
    fileKey?: number
    references: Reference[]
    selected?: number | null
    onselect?: (index: number) => void
    height?: string
  } = $props()

  const COLORS = { field: '#3987e5', new: '#16a34a', skip: '#9ca3af' }

  let container: HTMLDivElement
  let map = $state<MapLibreMap>()
  let basemap = $state<Basemap>('imagery')

  const data = () => ({
    type: 'FeatureCollection' as const,
    features: shapes.flatMap((shape, index) => [
      {
        type: 'Feature' as const,
        id: index,
        properties: { index, state: shape.state, selected: index === selected, label: '' },
        geometry: shape.boundary,
      },
      {
        type: 'Feature' as const,
        properties: { index, state: shape.state, selected: index === selected, label: shape.label },
        geometry: { type: 'Point' as const, coordinates: boundaryCenter(shape.boundary) },
      },
    ]),
  })

  /** Fit the map to every shape */
  export function fit() {
    if (!map || !shapes.length) return
    const corners = shapes.flatMap((shape) => boundaryBounds(shape.boundary))
    const lngs = corners.map(([lng]) => lng)
    const lats = corners.map(([, lat]) => lat)
    const bounds: [LngLat, LngLat] = [
      [Math.min(...lngs), Math.min(...lats)],
      [Math.max(...lngs), Math.max(...lats)],
    ]
    map.fitBounds(bounds, { padding: 48, maxZoom: 16, duration: 0 })
  }

  function addLayers(m: MapLibreMap) {
    addReferenceLayers(m, references)
    const color = ['match', ['get', 'state'], 'field', COLORS.field, 'new', COLORS.new, COLORS.skip]
    m.addSource('shapes', { type: 'geojson', data: data() as never })
    m.addLayer({
      id: 'shapes-fill',
      type: 'fill',
      source: 'shapes',
      filter: ['!=', ['geometry-type'], 'Point'],
      paint: { 'fill-color': color as never, 'fill-opacity': ['case', ['get', 'selected'], 0.5, 0.3] },
    })
    m.addLayer({
      id: 'shapes-line',
      type: 'line',
      source: 'shapes',
      filter: ['!=', ['geometry-type'], 'Point'],
      paint: { 'line-color': color as never, 'line-width': ['case', ['get', 'selected'], 4, 2] },
    })
    m.addLayer({
      id: 'shapes-label',
      type: 'symbol',
      source: 'shapes',
      filter: ['==', ['geometry-type'], 'Point'],
      layout: { 'text-field': ['get', 'label'], 'text-size': 13, 'text-font': LABEL_FONT },
      paint: { 'text-color': '#ffffff', 'text-halo-color': '#000000', 'text-halo-width': 1.5 },
    })
    m.on('click', 'shapes-fill', (event) => {
      const index = event.features?.[0]?.properties?.index
      if (typeof index === 'number') onselect?.(index)
    })
    m.on('mouseenter', 'shapes-fill', () => (m.getCanvas().style.cursor = 'pointer'))
    m.on('mouseleave', 'shapes-fill', () => (m.getCanvas().style.cursor = ''))
  }

  async function changeBasemap(next: Basemap) {
    if (!map || next === basemap) return
    basemap = next
    await setBasemap(map, next, (id) => id === 'reference' || id === 'shapes')
  }

  onMount(() => {
    let removed = false
    loadMapLibre().then((maplibre) => {
      if (removed) return
      const m = new maplibre.Map({
        container,
        style: basemapStyle(basemap),
        center: [-89.5, 44.25],
        zoom: 8,
        attributionControl: { compact: true, customAttribution: GEOCODER_ATTRIBUTION },
      })
      m.addControl(new maplibre.NavigationControl({ showCompass: false }), 'top-right')
      m.on('load', () => {
        map = m
        addLayers(m)
        fit()
      })
    })
    return () => {
      removed = true
      map?.remove()
    }
  })

  // A changed choice or selection recolors the shapes; a new file (fileKey) also fits the map to them
  $effect(() => {
    void [shapes, selected]
    untrack(() => map?.getSource<GeoJSONSource>('shapes')?.setData(data() as never))
  })
  $effect(() => {
    void fileKey
    untrack(fit)
  })
</script>

<div class="relative overflow-hidden rounded-lg border border-line" style:height>
  <div
    bind:this={container}
    class="h-full w-full"
    role="img"
    aria-label="Map of the file's shapes, numbered as in the list below"
  ></div>
  <div class="absolute top-2 left-2">
    <BasemapToggle value={basemap} onchange={changeBasemap} />
  </div>
</div>
