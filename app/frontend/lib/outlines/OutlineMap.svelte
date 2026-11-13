<script module lang="ts">
  export type DrawMode = 'view' | 'draw' | 'edit'
</script>

<script lang="ts">
  import 'maplibre-gl/dist/maplibre-gl.css'

  import { onMount, untrack } from 'svelte'
  import type { GeoJSONSource, Map as MapLibreMap } from 'maplibre-gl'
  import type { GeoJSONStoreFeatures, TerraDraw as TerraDrawClass } from 'terra-draw'

  import Button from '@/lib/components/Button.svelte'
  import { GEOCODER_ATTRIBUTION } from '@/lib/geocode'
  import { type Boundary, boundaryBounds, boundaryFrom, boundaryRing, type LngLat, pathCrossesItself } from '@/lib/geo'
  import { basemapStyle, type Basemap, setBasemap } from '@/lib/map/basemaps'
  import BasemapToggle from '@/lib/map/BasemapToggle.svelte'
  import { loadMapLibre } from '@/lib/map/maplibre'
  import { SOIL_SOURCE, SoilTypesLayer, viewArea } from '@/lib/map/soilTypes.svelte'
  import SoilTypesHover from '@/lib/map/SoilTypesHover.svelte'
  import SoilTypesLegend from '@/lib/map/SoilTypesLegend.svelte'
  import SoilTypesToggle from '@/lib/map/SoilTypesToggle.svelte'

  import { addReferenceLayers, FIRST_REFERENCE_LAYER, type Reference, referenceBounds } from './references'

  // A field's outline on the map (PLAN.md Phase 8 G.10, G.14: one polygon), drawn in white as fields
  // are on the overview map, its system in the system color. terra-draw holds it: shown as it is
  // ('view'), a new one clicked corner by corner ('draw'; the old one stays until the new one is
  // finished, which replaces it), or selected to drag it whole or by its corners, add one from a
  // midpoint or remove one ('edit'). Drawing and editing end with the map's own Done editing or Cancel (the
  // shape as it was), which don't submit the page. Corners go anywhere: a shape whose edges cross
  // turns orange, and can't be kept. The saved shape stays dashed under one that's changed.
  let {
    boundary = $bindable(),
    mode = $bindable(),
    saved = null,
    references,
    soilTypes,
    ready = $bindable(false),
    height = '32rem',
  }: {
    boundary: Boundary | null
    mode: DrawMode
    /** The shape as saved, shown dashed while the one on the map differs */
    saved?: Boundary | null
    /** The field's own system first (drawn more strongly), then the others */
    references: Reference[]
    /** Names for the Soil types layer */
    soilTypes: { key: string; name: string }[]
    /** Set once the map and drawing tools are ready */
    ready?: boolean
    height?: string
  } = $props()

  type Hex = `#${string}`
  // A field on the map (--color-map-field), on a dark edge
  const FIELD: Hex = '#ffffff'
  const EDGE: Hex = '#000000'
  // A shape whose edges cross (the caution status color)
  const CROSSED: Hex = '#e49e22'
  const OWN_SOURCES = ['reference', 'saved', 'shape-edge', SOIL_SOURCE]
  // Wisconsin's Central Sands, where most WISP fields are
  const DEFAULT_VIEW = { center: [-89.5, 44.25] as LngLat, zoom: 8 }

  let container: HTMLDivElement
  let map = $state<MapLibreMap>()
  let draw: TerraDrawClass | undefined
  let basemap = $state<Basemap>('imagery')
  // The outline as terra-draw last gave it, so the page's own changes (an import) can be told apart
  let written = untrack(() => JSON.stringify(boundary))
  const soilLayer = new SoilTypesLayer(() => soilTypes, viewArea, FIRST_REFERENCE_LAYER)

  const crossing = $derived(boundary ? pathCrossesItself(boundaryRing(boundary)) : false)

  /** Fit the map to the outline, or else the field's system */
  export function fit() {
    if (!map) return
    const own = references[0]
    const area = boundary ? boundaryBounds(boundary) : own ? referenceBounds(own) : null
    if (area) map.fitBounds(area, { padding: 48, maxZoom: 16, duration: 0 })
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

  // Whether a feature's edges cross: while it's being drawn, the corners placed and the edge to the
  // pointer, not the edge closing it back to the first corner (an L would cross that halfway)
  function crossed(feature: GeoJSONStoreFeatures) {
    if (feature.geometry.type !== 'Polygon') return false
    const ring = (feature.geometry.coordinates as LngLat[][])[0]
    return pathCrossesItself(feature.properties.currentlyDrawing ? ring.slice(0, -1) : ring)
  }
  const colored = (normal: Hex) => (feature: GeoJSONStoreFeatures) => (crossed(feature) ? CROSSED : normal)

  // Under terra-draw's white line: a dark edge, so the shape shows on the streets map too, and the
  // saved shape, dashed, while the one on the map differs
  const collection = (geometry: Boundary | null) => ({
    type: 'FeatureCollection' as const,
    features: geometry ? [{ type: 'Feature' as const, properties: {}, geometry }] : [],
  })
  const savedChanged = $derived(JSON.stringify(saved) !== JSON.stringify(boundary))
  function addShapeLayers(m: MapLibreMap) {
    m.addSource('shape-edge', { type: 'geojson', data: collection(boundary) as never })
    m.addLayer({
      id: 'shape-edge',
      type: 'line',
      source: 'shape-edge',
      paint: { 'line-color': EDGE, 'line-width': 4.5, 'line-opacity': 0.6 },
    })
    m.addSource('saved', { type: 'geojson', data: collection(savedChanged ? saved : null) as never })
    m.addLayer({
      id: 'saved-line',
      type: 'line',
      source: 'saved',
      paint: { 'line-color': FIELD, 'line-width': 2, 'line-opacity': 0.85, 'line-dasharray': [1, 1.5] },
    })
  }
  $effect(() => {
    const [shape, old] = [collection(boundary), collection(savedChanged ? saved : null)]
    if (!map) return
    map.getSource<GeoJSONSource>('shape-edge')?.setData(shape as never)
    map.getSource<GeoJSONSource>('saved')?.setData(old as never)
  })

  async function startDraw(m: MapLibreMap) {
    const { TerraDraw, TerraDrawPolygonMode, TerraDrawSelectMode } = await import('terra-draw')
    const { TerraDrawMapLibreGLAdapter } = await import('terra-draw-maplibre-gl-adapter')
    const style = {
      fillColor: colored(FIELD),
      fillOpacity: 0.15,
      outlineColor: colored(FIELD),
      outlineWidth: 2.5,
    }
    draw = new TerraDraw({
      adapter: new TerraDrawMapLibreGLAdapter({ map: m, coordinatePrecision: 7 }),
      modes: [
        new TerraDrawPolygonMode({
          styles: { ...style, closingPointColor: FIELD, closingPointOutlineColor: EDGE, closingPointWidth: 6 },
        }),
        new TerraDrawSelectMode({
          // Editing keeps the shape selected, its corners showing
          allowManualDeselection: false,
          flags: {
            polygon: {
              feature: {
                // The whole outline drags, its corners and midpoints too
                draggable: true,
                coordinates: { midpoints: true, draggable: true, deletable: true },
              },
            },
          },
          styles: {
            selectedPolygonColor: colored(FIELD),
            selectedPolygonFillOpacity: 0.2,
            selectedPolygonOutlineColor: colored(FIELD),
            selectedPolygonOutlineWidth: 3,
            selectionPointColor: FIELD,
            selectionPointOutlineColor: EDGE,
            selectionPointWidth: 6,
            selectionPointOutlineWidth: 2,
            midPointColor: EDGE,
            midPointOutlineColor: FIELD,
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

  // terra-draw's mode for ours; editing selects the shape so its corners show at once
  function applyMode() {
    if (!draw) return
    const wanted = mode === 'draw' ? 'polygon' : mode === 'edit' ? 'select' : 'static'
    if (draw.getMode() !== wanted) draw.setMode(wanted)
    if (mode !== 'edit') return
    const shape = draw.getSnapshot().find((feature) => feature.geometry.type === 'Polygon')
    if (shape && !shape.properties.selected) draw.selectFeature(shape.id!)
  }

  // The shape when drawing or editing started, for Cancel
  let before: Boundary | null = untrack(() => boundary)
  let previousMode: DrawMode = untrack(() => mode)
  $effect(() => {
    const now = mode
    untrack(() => {
      if (previousMode === 'view' && now !== 'view') before = boundary
      previousMode = now
      applyMode()
    })
  })

  function keep() {
    mode = 'view'
  }

  function cancel() {
    boundary = before
    written = JSON.stringify(before)
    mode = 'view'
    loadDraw()
  }

  // terra-draw's layers don't survive a new style: it stops for the switch and starts again with what
  // it held (only around a switch that happens: setBasemap skips one a later click replaced)
  function changeBasemap(next: Basemap) {
    if (!map || next === basemap) return
    basemap = next
    let snapshot: GeoJSONStoreFeatures[] = []
    setBasemap(map, next, (id) => OWN_SOURCES.includes(id), {
      before: () => {
        // The finished shape only: not one half drawn, nor the corner and midpoint handles
        snapshot = (draw?.getSnapshot() ?? [])
          .filter((feature) => feature.properties.mode === 'polygon' && !feature.properties.currentlyDrawing)
          .map((feature) => ({ ...feature, properties: { mode: 'polygon' } }))
        draw?.stop()
      },
      after: () => {
        if (!draw) return
        draw.start()
        loading = true
        try {
          if (snapshot.length) draw.addFeatures(snapshot)
        } finally {
          loading = false
        }
        applyMode()
      },
    })
  }

  onMount(() => {
    let removed = false
    loadMapLibre().then((maplibre) => {
      if (removed) return
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
        addShapeLayers(m)
        soilLayer.attach(m)
        fit()
        startDraw(m)
      })
    })
    return () => {
      removed = true
      draw?.stop()
      map?.remove()
    }
  })

  // The page changed the outline (an import, Remove): load it and show it
  $effect(() => {
    const json = JSON.stringify(boundary)
    if (json === written) return
    written = json
    untrack(() => {
      loadDraw()
      fit()
    })
  })
</script>

<div class="space-y-2">
  <div class="relative overflow-hidden rounded-lg border border-line" style:height>
    <div
      bind:this={container}
      class="h-full w-full"
      role="application"
      aria-label="Map of the field's shape: draw it here, or import it from a file above"
    ></div>
    <div class="absolute top-2 left-2 flex gap-2">
      <BasemapToggle value={basemap} onchange={changeBasemap} />
      <SoilTypesToggle layer={soilLayer} />
    </div>
    <SoilTypesHover layer={soilLayer} />
    {#if mode !== 'view'}
      <div
        class="absolute bottom-2 left-2 flex max-w-[calc(100%-1rem)] flex-wrap items-center gap-2 rounded-lg border border-line bg-surface-raised p-2 shadow-lg"
        role="group"
        aria-label="The shape on the map"
      >
        {#if mode === 'edit'}
          <Button type="button" disabled={crossing || !boundary} onclick={keep}>Done editing</Button>
        {/if}
        <Button type="button" variant="secondary" onclick={cancel}>Cancel</Button>
        {#if mode === 'edit' && crossing}
          <span class="text-sm text-status-caution-ink">Its edges cross: move a corner to fix it.</span>
        {:else if mode === 'draw'}
          <span class="text-sm text-ink-muted">Click the first corner again, or press Enter, to finish.</span>
        {/if}
      </div>
    {/if}
  </div>
  <SoilTypesLegend layer={soilLayer} {soilTypes} zoomHint="zoom in to see them." />
</div>
