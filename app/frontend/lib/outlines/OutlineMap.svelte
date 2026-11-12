<script module lang="ts">
  export type DrawMode = 'view' | 'draw' | 'edit'
  export type MapPin = { id: number; label: string; at: LngLat | null }
</script>

<script lang="ts">
  import 'maplibre-gl/dist/maplibre-gl.css'

  import { onMount, untrack } from 'svelte'
  import type { Map as MapLibreMap, Marker as MarkerClass } from 'maplibre-gl'
  import type { GeoJSONStoreFeatures, TerraDraw as TerraDrawClass } from 'terra-draw'

  import { GEOCODER_ATTRIBUTION } from '@/lib/geocode'
  import { type Boundary, boundaryBounds, boundaryFrom, boundaryRing, type LngLat } from '@/lib/geo'
  import { basemapStyle, type Basemap, setBasemap } from '@/lib/map/basemaps'
  import BasemapToggle from '@/lib/map/BasemapToggle.svelte'
  import { loadMapLibre } from '@/lib/map/maplibre'
  import PlaceSearch from '@/lib/map/PlaceSearch.svelte'

  import { addReferenceLayers, type Reference, referenceBounds } from './references'

  // A field's outline on the map (PLAN.md Phase 8 G.10, G.14: one polygon). terra-draw holds it:
  // shown as it is ('view'), a new one clicked corner by corner ('draw'; the old one stays until the
  // new one is finished, which replaces it), or selected to drag its corners, add one from a
  // midpoint or remove one ('edit'). The field's irrigation system, the operation's other systems and
  // fields are drawn for reference, and its plots' pins are markers: dragged, or placed by a click
  // while one is being pinned.
  let {
    boundary = $bindable(),
    mode = $bindable(),
    references,
    pins = [],
    pinning = null,
    onpin,
    ready = $bindable(false),
    height = '32rem',
  }: {
    boundary: Boundary | null
    mode: DrawMode
    /** The field's own system first (outlined more strongly), then the others */
    references: Reference[]
    pins?: MapPin[]
    /** The plot being pinned: the next click places it */
    pinning?: number | null
    onpin?: (id: number, at: LngLat) => void
    /** Set once the map and drawing tools are ready */
    ready?: boolean
    height?: string
  } = $props()

  const COLOR = '#3987e5'
  const OWN_SOURCES = ['reference']
  // Wisconsin's Central Sands, where most WISP fields are
  const DEFAULT_VIEW = { center: [-89.5, 44.25] as LngLat, zoom: 8 }

  let container: HTMLDivElement
  let map = $state<MapLibreMap>()
  let draw: TerraDrawClass | undefined
  let Marker: typeof MarkerClass | undefined
  // eslint-disable-next-line svelte/prefer-svelte-reactivity -- bookkeeping for MapLibre's markers, not rendered from
  const markers = new Map<number, MarkerClass>()
  let basemap = $state<Basemap>('imagery')
  let placeSearch = $state<PlaceSearch>()
  // The outline as terra-draw last gave it, so the page's own changes (an import) can be told apart
  let written = untrack(() => JSON.stringify(boundary))

  /** Fit the map to the outline, or else the field's system */
  export function fit() {
    if (!map) return
    const own = references[0]
    const area = boundary ? boundaryBounds(boundary) : own ? referenceBounds(own) : null
    if (area) map.fitBounds(area, { padding: 48, maxZoom: 16, duration: 0 })
  }

  /** Scroll the map into view (to place a pin with a click) */
  export function show() {
    container.scrollIntoView({ block: 'nearest', behavior: 'smooth' })
  }

  // terra-draw's finished polygon as the outline (there's only ever one once a drawing finishes)
  function readDraw() {
    if (!draw || loading) return
    const ring = draw
      .getSnapshot()
      .filter((feature) => feature.geometry.type === 'Polygon' && !feature.properties.currentlyDrawing)
      .map((feature) => (feature.geometry.coordinates as LngLat[][])[0])
      .find((ring) => ring.length >= 4)
    const outline = ring ? boundaryFrom(ring) : null
    written = JSON.stringify(outline)
    boundary = outline
  }

  // A finished drawing replaces the outline it was drawn over
  function keepOnly(id: string | number) {
    const others = draw!.getSnapshot().filter((feature) => feature.id !== id && feature.geometry.type === 'Polygon')
    if (!others.length) return
    loading = true
    try {
      draw!.removeFeatures(others.map((feature) => feature.id!))
    } finally {
      loading = false
    }
  }

  // The outline into terra-draw (after the page changed it, or a basemap change cleared it)
  // terra-draw's change events while it's loaded are its own, not edits
  let loading = false

  function loadDraw() {
    if (!draw) return
    loading = true
    try {
      draw.clear()
      if (!boundary) return
      const feature: GeoJSONStoreFeatures = {
        id: crypto.randomUUID(),
        type: 'Feature',
        geometry: { type: 'Polygon', coordinates: [boundaryRing(boundary)] },
        properties: { mode: 'polygon' },
      }
      const refused = draw.addFeatures([feature]).filter((result) => !result.valid)
      if (refused.length) console.warn('An outline terra-draw refused:', refused)
    } finally {
      loading = false
    }
  }

  async function startDraw(m: MapLibreMap) {
    const { TerraDraw, TerraDrawPolygonMode, TerraDrawSelectMode, ValidateNotSelfIntersecting } =
      await import('terra-draw')
    const { TerraDrawMapLibreGLAdapter } = await import('terra-draw-maplibre-gl-adapter')
    const validation = (feature: GeoJSONStoreFeatures) => ValidateNotSelfIntersecting(feature)
    const style = {
      fillColor: COLOR,
      fillOpacity: 0.3,
      outlineColor: COLOR,
      outlineWidth: 2.5,
    } as const
    draw = new TerraDraw({
      adapter: new TerraDrawMapLibreGLAdapter({ map: m, coordinatePrecision: 7 }),
      modes: [
        new TerraDrawPolygonMode({
          validation,
          styles: { ...style, closingPointColor: '#ffffff', closingPointOutlineColor: COLOR, closingPointWidth: 6 },
        }),
        new TerraDrawSelectMode({
          flags: {
            polygon: {
              feature: {
                validation,
                draggable: false,
                coordinates: { midpoints: true, draggable: true, deletable: true },
              },
            },
          },
          styles: {
            selectedPolygonColor: COLOR,
            selectedPolygonFillOpacity: 0.35,
            selectedPolygonOutlineColor: '#1c5cab',
            selectedPolygonOutlineWidth: 3,
            selectionPointColor: '#1c5cab',
            selectionPointOutlineColor: '#ffffff',
            selectionPointWidth: 6,
            selectionPointOutlineWidth: 2,
            midPointColor: '#ffffff',
            midPointOutlineColor: '#1c5cab',
            midPointWidth: 4,
          },
        }),
      ],
    })
    draw.start()
    draw.on('change', (_ids, type) => {
      if (type !== 'styling') readDraw()
    })
    // A finished outline replaces the old one and is ready to adjust
    draw.on('finish', (id) => {
      keepOnly(id)
      readDraw()
      mode = 'edit'
    })
    loadDraw()
    applyMode()
    ready = true
  }

  function applyMode() {
    if (!draw) return
    const wanted = mode === 'draw' ? 'polygon' : mode === 'edit' ? 'select' : 'static'
    if (draw.getMode() !== wanted) draw.setMode(wanted)
  }

  async function changeBasemap(next: Basemap) {
    if (!map || next === basemap) return
    basemap = next
    const snapshot = draw?.getSnapshot() ?? []
    draw?.stop()
    await setBasemap(map, next, (id) => OWN_SOURCES.includes(id))
    draw?.start()
    if (snapshot.length) draw?.addFeatures(snapshot.filter((feature) => !feature.properties.currentlyDrawing))
    applyMode()
  }

  function placePins() {
    if (!map || !Marker) return
    for (const [id, marker] of markers) {
      if (!pins.some((pin) => pin.id === id && pin.at)) {
        marker.remove()
        markers.delete(id)
      }
    }
    for (const pin of pins) {
      if (!pin.at) continue
      const existing = markers.get(pin.id)
      if (existing) {
        existing.setLngLat(pin.at)
        continue
      }
      const element = document.createElement('div')
      element.className =
        'rounded-full border-2 border-white bg-[#7c3aed] px-2 py-0.5 text-xs font-medium text-white shadow cursor-grab'
      element.textContent = pin.label
      element.title = `${pin.label}: drag to move`
      const marker = new Marker({ element, draggable: true }).setLngLat(pin.at).addTo(map)
      marker.on('dragend', () => {
        const { lng, lat } = marker.getLngLat()
        onpin?.(pin.id, [lng, lat])
      })
      markers.set(pin.id, marker)
    }
  }

  onMount(() => {
    let removed = false
    loadMapLibre().then((maplibre) => {
      if (removed) return
      Marker = maplibre.Marker
      const m = new maplibre.Map({
        container,
        style: basemapStyle(basemap),
        center: DEFAULT_VIEW.center,
        zoom: DEFAULT_VIEW.zoom,
        attributionControl: { compact: true, customAttribution: GEOCODER_ATTRIBUTION },
        // Double-clicks finish drawing rather than zoom
        doubleClickZoom: false,
      })
      m.addControl(new maplibre.NavigationControl({ showCompass: false }), 'top-right')
      m.on('load', () => {
        map = m
        addReferenceLayers(m, references)
        fit()
        startDraw(m)
        placePins()
      })
      // A click places the plot being pinned. Listened for on the canvas itself, as terra-draw takes
      // the map's pointer events.
      m.getCanvasContainer().addEventListener(
        'click',
        (event) => {
          if (pinning === null || mode !== 'view') return
          const box = m.getCanvasContainer().getBoundingClientRect()
          const { lng, lat } = m.unproject([event.clientX - box.left, event.clientY - box.top])
          onpin?.(pinning, [lng, lat])
        },
        { capture: true },
      )
    })
    return () => {
      removed = true
      draw?.stop()
      map?.remove()
    }
  })

  // The page changed the outline (an import, "Same as", Start over): load it and show it
  $effect(() => {
    const json = JSON.stringify(boundary)
    if (json === written) return
    written = json
    untrack(() => {
      loadDraw()
      fit()
    })
  })

  $effect(() => {
    void mode
    untrack(applyMode)
  })

  $effect(() => {
    void pins
    untrack(placePins)
  })

  $effect(() => {
    if (map) map.getCanvas().style.cursor = pinning !== null && mode === 'view' ? 'crosshair' : ''
  })
</script>

<div class="relative overflow-hidden rounded-lg border border-line" style:height>
  <div
    bind:this={container}
    class="h-full w-full"
    role="application"
    aria-label="Map of the field's outline: draw it here, or use Same as the irrigation system or Import from a file above"
  ></div>
  <div class="absolute top-2 left-2">
    <BasemapToggle value={basemap} onchange={changeBasemap} />
  </div>
  <div class="absolute bottom-2 left-2 w-[min(18rem,calc(100%-6rem))]">
    <PlaceSearch bind:this={placeSearch} {map} maxZoom={15} />
  </div>
</div>
