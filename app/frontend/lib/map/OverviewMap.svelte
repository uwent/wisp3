<script module lang="ts">
  /** Our sources (irrigation groups, fields, pivots, pins, and overlays named overlay-*), carried over when the basemap changes */
  export const isOwnSource = (id: string) =>
    ['pivots', 'groups', 'fields', 'pins'].includes(id) || id.startsWith('overlay-')
  export const PIVOT_LAYER = 'pivots-fill'
  /** Point kinds' dots (a traveler, drip, a location) */
  export const POINT_LAYER = 'pivots-point'
  /** Fields with an outline (G.10); overlays go under them */
  export const FIELD_LAYER = 'fields-fill'
  /** Plots with a pin (G.10) */
  export const PIN_LAYER = 'pins'
  /** The systems' own layers, which the Irrigation systems layer switch shows and hides */
  const SYSTEM_LAYERS = [PIVOT_LAYER, 'pivots-casing', 'pivots-line', POINT_LAYER]
</script>

<script lang="ts">
  import 'maplibre-gl/dist/maplibre-gl.css'

  import { mount, onMount, type Snippet, unmount } from 'svelte'
  import type { ExpressionSpecification, GeoJSONSource, Map as MapLibreMap, MapMouseEvent, Marker } from 'maplibre-gl'

  import { readPalette } from '@/lib/charts/palette'
  import type { LngLat } from '@/lib/geo'
  import { GEOCODER_ATTRIBUTION } from '@/lib/geocode'
  import { onThemeChange } from '@/lib/theme'
  import type { UnitSystem } from '@/lib/units'

  import { basemapStyle, type Basemap, LABEL_FONT, setBasemap } from './basemaps'
  import BasemapToggle from './BasemapToggle.svelte'
  import { ButtonControl, FIT_ICON } from './controls'
  import { loadMapLibre } from './maplibre'
  import PivotMarker from './PivotMarker.svelte'
  import {
    allOutlined,
    type FeatureCollection,
    fieldFeatures,
    type MapPivot,
    pinFeatures,
    pivotBounds,
    pivotFeatures,
  } from './pivots'
  import PlaceSearch from './PlaceSearch.svelte'

  // The operation's irrigation systems on a map (PLAN.md Phase 7): each drawn to scale in its most
  // urgent field's status color (a point kind as a dot), with a marker of its fields' badges at the
  // center, and each irrigation group lightly outlined around its systems. Fields with an outline
  // (G.10) are filled in their status instead, the system then drawn as a line over them, and its
  // marker shows only the fields without one; plots with a pin are dots in their status. Clicking a
  // system selects it, and clicking a field or pin selects its system with that field; the page
  // shows its details in the panel (children) and the toolbar adds to the top-left.
  let {
    pivots,
    groups,
    selectedId,
    selectedFieldId = null,
    highlighted,
    showSystems = true,
    basemap,
    view,
    unitSystem = 'imperial',
    onselect,
    onbasemap,
    onviewchange,
    onload,
    toolbar,
    children,
  }: {
    pivots: MapPivot[]
    /** The irrigation groups' outlines (groupFeatures) */
    groups: FeatureCollection<{ name: string }>
    selectedId: number | null
    /** The field selected with its system (G.10), highlighted on the map */
    selectedFieldId?: number | null
    /** The pivots in the "needs water within" window (others are dimmed), or null for none */
    highlighted: Set<number> | null
    /** Draw the systems' shapes and dots (the Irrigation systems layer) */
    showSystems?: boolean
    basemap: Basemap
    /** Where to start; without one the map fits every pivot */
    view: { center: LngLat; zoom: number } | null
    unitSystem?: UnitSystem
    onselect: (pivotId: number | null, fieldId?: number | null) => void
    onbasemap: (basemap: Basemap) => void
    onviewchange: (view: { center: LngLat; zoom: number }) => void
    /** Once the map and our layers are on it, and again after a basemap change */
    onload?: (map: MapLibreMap) => void
    toolbar?: Snippet
    children?: Snippet
  } = $props()

  // Below FAR_ZOOM a pivot is a few pixels across: its marker is one dot. Below NAME_ZOOM the
  // marker shows badges without the pivot's name.
  const FAR_ZOOM = 11.5
  const NAME_ZOOM = 13
  const PIVOT_ZOOM = 14
  // Wisconsin's Central Sands, where most WISP pivots are
  const DEFAULT_VIEW = { center: [-89.5, 44.25] as LngLat, zoom: 8 }

  let wrapper: HTMLDivElement
  let container: HTMLDivElement
  let map = $state<MapLibreMap>()
  let zoom = $state(DEFAULT_VIEW.zoom)
  let placeSearch = $state<PlaceSearch>()

  type MarkerProps = { pivot: MapPivot; selected: boolean; dimmed: boolean; onselect: () => void }
  // eslint-disable-next-line svelte/prefer-svelte-reactivity -- bookkeeping for MapLibre's markers, not rendered from
  const markers = new Map<number, { marker: Marker; props: MarkerProps; component: ReturnType<typeof mount> }>()

  const features = () => pivotFeatures(pivots, selectedId, highlighted)
  const fields = () => fieldFeatures(pivots, selectedFieldId, highlighted)
  const pins = () => pinFeatures(pivots, selectedFieldId, highlighted)

  function statusColor(): ExpressionSpecification {
    const { status } = readPalette()
    return [
      'match',
      ['get', 'status'],
      'irrigate',
      status.irrigate,
      'caution',
      status.caution,
      'needs_canopy',
      status.caution,
      'ok',
      status.ok,
      'full',
      status.full,
      '#9ca3af',
    ]
  }

  const POLYGONS: ExpressionSpecification = ['==', ['geometry-type'], 'Polygon']

  function addPivotLayers(m: MapLibreMap) {
    // Irrigation groups: a light shade inside a dotted line, named along it
    m.addSource('groups', { type: 'geojson', data: groups })
    m.addLayer({
      id: 'groups-fill',
      type: 'fill',
      source: 'groups',
      paint: { 'fill-color': '#ffffff', 'fill-opacity': 0.08 },
    })
    m.addLayer({
      id: 'groups-casing',
      type: 'line',
      source: 'groups',
      paint: { 'line-color': '#000000', 'line-width': 3, 'line-opacity': 0.3 },
    })
    m.addLayer({
      id: 'groups-line',
      type: 'line',
      source: 'groups',
      paint: { 'line-color': '#ffffff', 'line-width': 1.5, 'line-dasharray': [1, 2] },
      layout: { 'line-cap': 'round' },
    })
    m.addLayer({
      id: 'groups-label',
      type: 'symbol',
      source: 'groups',
      layout: {
        'symbol-placement': 'line',
        'text-field': ['get', 'name'],
        'text-size': 12,
        'text-font': LABEL_FONT,
        'text-offset': [0, -0.8],
      },
      paint: { 'text-color': '#ffffff', 'text-halo-color': '#000000', 'text-halo-width': 1.2 },
    })

    // Fields with an outline: filled in their status, under the systems (G.10)
    const color = statusColor()
    m.addSource('fields', { type: 'geojson', data: fields() as never })
    const OUTLINES: ExpressionSpecification = ['==', ['get', 'kind'], 'outline']
    m.addLayer({
      id: FIELD_LAYER,
      type: 'fill',
      source: 'fields',
      filter: OUTLINES,
      paint: {
        'fill-color': color,
        'fill-opacity': ['case', ['get', 'dimmed'], 0.05, ['get', 'selected'], 0.5, 0.3],
      },
    })
    m.addLayer({
      id: 'fields-line',
      type: 'line',
      source: 'fields',
      filter: OUTLINES,
      paint: {
        'line-color': ['case', ['get', 'selected'], '#ffffff', color],
        'line-width': ['case', ['get', 'selected'], 3, 1.5],
        'line-opacity': ['case', ['get', 'dimmed'], 0.35, 1],
      },
    })
    m.addLayer({
      id: 'fields-label',
      type: 'symbol',
      source: 'fields',
      filter: ['==', ['get', 'kind'], 'label'],
      minzoom: NAME_ZOOM,
      layout: { 'text-field': ['get', 'name'], 'text-size': 12, 'text-font': LABEL_FONT },
      paint: { 'text-color': '#ffffff', 'text-halo-color': '#000000', 'text-halo-width': 1.2 },
    })

    m.addSource('pivots', { type: 'geojson', data: features() })
    m.addLayer({
      id: PIVOT_LAYER,
      type: 'fill',
      source: 'pivots',
      filter: POLYGONS,
      paint: {
        'fill-color': color,
        // A system whose fields have outlines leaves the status to them
        'fill-opacity': ['case', ['get', 'outlined'], 0, ['get', 'dimmed'], 0.05, ['get', 'selected'], 0.4, 0.22],
      },
    })
    // A white casing under the status line keeps it visible on imagery
    m.addLayer({
      id: 'pivots-casing',
      type: 'line',
      source: 'pivots',
      filter: POLYGONS,
      paint: {
        'line-color': '#ffffff',
        'line-width': ['case', ['get', 'selected'], 6, 3.5],
        'line-opacity': ['case', ['get', 'dimmed'], 0.3, 0.85],
      },
    })
    m.addLayer({
      id: 'pivots-line',
      type: 'line',
      source: 'pivots',
      filter: POLYGONS,
      paint: {
        'line-color': color,
        'line-width': ['case', ['get', 'selected'], 3.5, 2],
        'line-opacity': ['case', ['get', 'dimmed'], 0.35, 1],
      },
    })
    // A point kind (a traveler, drip, a location) is a dot under its marker, the same size at any zoom
    m.addLayer({
      id: POINT_LAYER,
      type: 'circle',
      source: 'pivots',
      filter: ['==', ['geometry-type'], 'Point'],
      paint: {
        'circle-color': color,
        'circle-radius': ['case', ['get', 'selected'], 22, 18],
        'circle-opacity': ['case', ['get', 'dimmed'], 0.1, ['get', 'selected'], 0.55, 0.35],
        'circle-stroke-color': '#ffffff',
        'circle-stroke-width': ['case', ['get', 'selected'], 3, 2],
        'circle-stroke-opacity': ['case', ['get', 'dimmed'], 0.3, 0.85],
      },
    })
    for (const layer of SYSTEM_LAYERS) m.setLayoutProperty(layer, 'visibility', showSystems ? 'visible' : 'none')

    // Plots with a pin, over everything, named when zoomed in
    m.addSource('pins', { type: 'geojson', data: pins() as never })
    m.addLayer({
      id: PIN_LAYER,
      type: 'circle',
      source: 'pins',
      // Plots are a few pixels apart until zoomed in
      minzoom: PIVOT_ZOOM,
      paint: {
        'circle-color': color,
        'circle-radius': ['case', ['get', 'selected'], 8, 6],
        'circle-opacity': ['case', ['get', 'dimmed'], 0.3, 1],
        'circle-stroke-color': '#ffffff',
        'circle-stroke-width': 2,
      },
    })
    m.addLayer({
      id: 'pins-label',
      type: 'symbol',
      source: 'pins',
      minzoom: PIVOT_ZOOM + 2,
      layout: {
        'text-field': ['get', 'name'],
        'text-size': 11,
        'text-font': LABEL_FONT,
        'text-anchor': 'left',
        'text-offset': [0.8, 0],
      },
      paint: { 'text-color': '#ffffff', 'text-halo-color': '#000000', 'text-halo-width': 1.2 },
    })
  }

  async function syncMarkers() {
    const m = map
    if (!m) return
    const { Marker } = await loadMapLibre()
    // A system's marker shows its fields without an outline, and goes once they all have one (G.10)
    const marked = pivots
      .filter((pivot) => !allOutlined(pivot))
      .map((pivot) => ({
        ...pivot,
        fields: pivot.fields.filter((card) => !pivot.outlines.some((outline) => outline.field_id === card.id)),
      }))
    const ids = new Set(marked.map((pivot) => pivot.id))
    for (const [id, entry] of markers) {
      if (ids.has(id)) continue
      entry.marker.remove()
      unmount(entry.component)
      markers.delete(id)
    }
    for (const pivot of marked) {
      const state = {
        pivot,
        selected: pivot.id === selectedId,
        dimmed: highlighted !== null && !highlighted.has(pivot.id),
      }
      const entry = markers.get(pivot.id)
      if (entry) {
        Object.assign(entry.props, state)
        continue
      }
      const element = document.createElement('div')
      const props: MarkerProps = $state({ ...state, onselect: () => onselect(pivot.id) })
      const component = mount(PivotMarker, { target: element, props })
      const marker = new Marker({ element, anchor: 'center' }).setLngLat([pivot.longitude, pivot.latitude]).addTo(m)
      markers.set(pivot.id, { marker, props, component })
    }
  }

  // Redraw when the pivots (farm filter), the selection or the window change
  $effect(() => {
    void [pivots, selectedId, selectedFieldId, highlighted]
    map?.getSource<GeoJSONSource>('pivots')?.setData(features())
    map?.getSource<GeoJSONSource>('fields')?.setData(fields() as never)
    map?.getSource<GeoJSONSource>('pins')?.setData(pins() as never)
    syncMarkers()
  })
  $effect(() => {
    const visibility = showSystems ? 'visible' : 'none'
    for (const layer of SYSTEM_LAYERS) if (map?.getLayer(layer)) map.setLayoutProperty(layer, 'visibility', visibility)
  })
  $effect(() => {
    map?.getSource<GeoJSONSource>('groups')?.setData(groups)
  })

  /** Fits the map to these pivots (all of them by default) */
  export function fit(some: MapPivot[] = pivots, animate = true) {
    const bounds = pivotBounds(some)
    if (bounds) map?.fitBounds(bounds, { padding: 60, maxZoom: PIVOT_ZOOM, duration: animate ? 800 : 0 })
  }

  /** Brings a pivot into view beside the panel that opens for it */
  export function show(pivotId: number) {
    const pivot = pivots.find((p) => p.id === pivotId)
    if (!map || !pivot) return
    const wide = wrapper.clientWidth >= 640
    map.flyTo({
      center: [pivot.longitude, pivot.latitude],
      zoom: Math.max(map.getZoom(), NAME_ZOOM + 0.5),
      offset: wide ? [-170, 0] : [0, -wrapper.clientHeight * 0.2],
    })
  }

  export const getMap = () => map

  async function changeBasemap(to: Basemap) {
    if (!map) return
    onbasemap(to)
    await setBasemap(map, to, isOwnSource)
    // The style's pivot layers have the palette of the old theme only if it changed meanwhile
    map.getSource<GeoJSONSource>('pivots')?.setData(features())
    map.getSource<GeoJSONSource>('fields')?.setData(fields() as never)
    map.getSource<GeoJSONSource>('pins')?.setData(pins() as never)
    onload?.(map)
  }

  function onClick(event: MapMouseEvent) {
    placeSearch?.close()
    if (!map) return
    // A pin or a field selects its system with that field; else a system, or nothing
    const layers = [PIN_LAYER, POINT_LAYER, FIELD_LAYER, PIVOT_LAYER].filter((layer) => map!.getLayer(layer))
    const hit = map.queryRenderedFeatures(event.point, { layers })[0]
    if (!hit) return onselect(null)
    const { properties } = hit
    if (hit.layer.id === PIN_LAYER || hit.layer.id === FIELD_LAYER)
      onselect(Number(properties.pivot_id), Number(hit.layer.id === PIN_LAYER ? properties.field_id : properties.id))
    else onselect(Number(properties.id))
  }

  onMount(() => {
    let disposed = false
    const cleanups: (() => void)[] = []

    loadMapLibre().then((maplibre) => {
      if (disposed) return
      const m = new maplibre.Map({
        container,
        style: basemapStyle(basemap),
        ...(view ?? DEFAULT_VIEW),
        attributionControl: false,
      })
      map = m
      m.addControl(new maplibre.AttributionControl({ compact: true, customAttribution: GEOCODER_ATTRIBUTION }))
      m.addControl(new maplibre.NavigationControl({ showCompass: false }), 'top-right')
      m.addControl(new ButtonControl('Fit all irrigation systems', FIT_ICON, () => fit()), 'top-right')
      m.addControl(
        new maplibre.GeolocateControl({ positionOptions: { enableHighAccuracy: true }, trackUserLocation: false }),
        'top-right',
      )
      m.addControl(new maplibre.FullscreenControl({ container: wrapper }), 'top-right')
      m.addControl(new maplibre.ScaleControl({ unit: unitSystem === 'metric' ? 'metric' : 'imperial' }), 'bottom-left')
      if (!view) fit(pivots, false)

      m.on('load', () => {
        addPivotLayers(m)
        syncMarkers()
        onload?.(m)
      })
      m.on('click', onClick)
      for (const layer of [PIVOT_LAYER, POINT_LAYER, FIELD_LAYER, PIN_LAYER]) {
        m.on('mouseenter', layer, () => (m.getCanvas().style.cursor = 'pointer'))
        m.on('mouseleave', layer, () => (m.getCanvas().style.cursor = ''))
      }
      m.on('zoom', () => (zoom = m.getZoom()))
      m.on('moveend', () => {
        const { lng, lat } = m.getCenter()
        onviewchange({ center: [lng, lat], zoom: Math.round(m.getZoom() * 100) / 100 })
      })
      zoom = m.getZoom()

      // The side list opening and closing resizes the map without resizing the window
      const resize = new ResizeObserver(() => m.resize())
      resize.observe(container)
      cleanups.push(() => resize.disconnect())

      // Status colors follow the light or dark theme
      cleanups.push(
        onThemeChange(() => {
          const color = statusColor()
          if (!m.getLayer(PIVOT_LAYER)) return
          m.setPaintProperty(PIVOT_LAYER, 'fill-color', color)
          m.setPaintProperty('pivots-line', 'line-color', color)
          m.setPaintProperty(POINT_LAYER, 'circle-color', color)
          m.setPaintProperty(FIELD_LAYER, 'fill-color', color)
          m.setPaintProperty('fields-line', 'line-color', ['case', ['get', 'selected'], '#ffffff', color])
          m.setPaintProperty(PIN_LAYER, 'circle-color', color)
        }),
      )
    })

    return () => {
      disposed = true
      cleanups.forEach((cleanup) => cleanup())
      for (const { component } of markers.values()) unmount(component)
      markers.clear()
      map?.remove()
    }
  })
</script>

<div
  bind:this={wrapper}
  class="group/map relative h-full w-full overflow-hidden bg-surface"
  data-far={zoom < FAR_ZOOM ? '' : undefined}
  data-mid={zoom >= FAR_ZOOM && zoom < NAME_ZOOM ? '' : undefined}
>
  <div
    bind:this={container}
    class="h-full w-full"
    role="application"
    aria-label="Map of the operation's pivots. Select a pivot to see its fields."
  ></div>

  <div class="pointer-events-none absolute top-2 left-2 flex w-[min(17rem,calc(100%-4rem))] flex-col gap-2">
    <div class="pointer-events-auto flex flex-wrap items-start gap-2">
      <BasemapToggle value={basemap} onchange={changeBasemap} />
      {@render toolbar?.()}
    </div>
    <div class="pointer-events-auto hidden sm:block">
      <PlaceSearch bind:this={placeSearch} {map} maxZoom={PIVOT_ZOOM - 1} />
    </div>
  </div>

  {@render children?.()}
</div>
