<script module lang="ts">
  /** Our sources (irrigation groups, fields, pivots, pins, and overlays named overlay-*), carried over when the basemap changes */
  export const isOwnSource = (id: string) =>
    ['pivots', 'groups', 'fields', 'pins'].includes(id) || id.startsWith('overlay-')
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
  import PlotMarker from './PlotMarker.svelte'
  import {
    allOutlined,
    type FeatureCollection,
    fieldFeatures,
    type MapPivot,
    pinFeatures,
    pivotBounds,
    pivotFeatures,
    type PlotPack,
    plotPacks,
  } from './pivots'
  import PlaceSearch from './PlaceSearch.svelte'
  import {
    addGlyphImages,
    addSystemLayers,
    FIELD_LAYER,
    hoverLabel,
    PIN_LAYER,
    setSystemColors,
    SYSTEM_LAYERS,
    systemHit,
  } from './systemLayers'

  // The operation's irrigation systems on a map (PLAN.md Phase 7, G.14): each drawn in the system
  // color, a pivot or linear to scale and a point kind as its glyph (systemLayers.ts), with a marker
  // of its fields' badges at the center, and each irrigation group lightly outlined around its
  // systems. Fields with an outline (G.10) are filled in their status, and its marker shows only the
  // fields without one. A field's pinned plots are packed as badges (PlotMarker), and up close are
  // dots in their status at their pins. Clicking a system selects it, and clicking a field, its
  // plots or a pin selects its system with that field; the page shows its details in the panel
  // (children) and the toolbar adds to the top-left.
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
  // From NAME_ZOOM to here a field's pinned plots are packed as badges under its name (PlotMarker);
  // from here on, each pin is at its place
  const SPREAD_ZOOM = 17
  // Wisconsin's Central Sands, where most WISP pivots are
  const DEFAULT_VIEW = { center: [-89.5, 44.25] as LngLat, zoom: 8 }

  let wrapper: HTMLDivElement
  let container: HTMLDivElement
  let map = $state<MapLibreMap>()
  let zoom = $state(DEFAULT_VIEW.zoom)
  let placeSearch = $state<PlaceSearch>()
  // What's under the pointer, named beside it
  let hover = $state<{ x: number; y: number; text: string } | null>(null)

  type MarkerProps = { pivot: MapPivot; selected: boolean; dimmed: boolean; onselect: () => void }
  // eslint-disable-next-line svelte/prefer-svelte-reactivity -- bookkeeping for MapLibre's markers, not rendered from
  const markers = new Map<number, { marker: Marker; props: MarkerProps; component: ReturnType<typeof mount> }>()
  type PlotProps = { pack: PlotPack; selected: boolean; dimmed: boolean; onselect: () => void }
  // eslint-disable-next-line svelte/prefer-svelte-reactivity -- as markers, by field
  const plotMarkers = new Map<number, { marker: Marker; props: PlotProps; component: ReturnType<typeof mount> }>()

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

  function addPivotLayers(m: MapLibreMap) {
    // Irrigation groups: a light shade inside a dashed line in the system color, named along it
    const palette = readPalette()
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
      paint: { 'line-color': palette.systemCasing, 'line-width': 4, 'line-opacity': 0.55 },
    })
    m.addLayer({
      id: 'groups-line',
      type: 'line',
      source: 'groups',
      paint: { 'line-color': palette.system, 'line-width': 2, 'line-dasharray': [3, 2] },
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
      paint: { 'text-color': palette.system, 'text-halo-color': palette.systemCasing, 'text-halo-width': 1.5 },
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

    addSystemLayers(m, features() as never, readPalette())
    for (const layer of SYSTEM_LAYERS) m.setLayoutProperty(layer, 'visibility', showSystems ? 'visible' : 'none')

    // Plots with a pin, over everything, named when zoomed in
    m.addSource('pins', { type: 'geojson', data: pins() as never })
    m.addLayer({
      id: PIN_LAYER,
      type: 'circle',
      source: 'pins',
      // Plots are a few pixels apart until zoomed in; until then PlotMarker packs them
      minzoom: SPREAD_ZOOM,
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
      minzoom: SPREAD_ZOOM,
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

    // A field's pinned plots, packed as badges until the map is close enough to spread them
    const packs = plotPacks(pivots)
    const fieldIds = new Set(packs.map((pack) => pack.field_id))
    for (const [id, entry] of plotMarkers) {
      if (fieldIds.has(id)) continue
      entry.marker.remove()
      unmount(entry.component)
      plotMarkers.delete(id)
    }
    for (const pack of packs) {
      const state = {
        pack,
        selected: pack.field_id === selectedFieldId,
        dimmed: highlighted !== null && !highlighted.has(pack.pivot_id),
      }
      const entry = plotMarkers.get(pack.field_id)
      if (entry) {
        Object.assign(entry.props, state)
        entry.marker.setLngLat(pack.center)
        continue
      }
      const element = document.createElement('div')
      const props: PlotProps = $state({ ...state, onselect: () => onselect(pack.pivot_id, pack.field_id) })
      const component = mount(PlotMarker, { target: element, props })
      // Under the field's name when it has an outline
      const marker = new Marker({
        element,
        anchor: pack.outlined ? 'top' : 'center',
        offset: [0, pack.outlined ? 10 : 0],
      })
        .setLngLat(pack.center)
        .addTo(m)
      plotMarkers.set(pack.field_id, { marker, props, component })
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
    // The new style has none of our icons
    addGlyphImages(map)
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
    const hit = systemHit(map, event.point)
    if (!hit) return onselect(null)
    if (hit.kind === 'system') onselect(hit.pivotId)
    else onselect(hit.pivotId, hit.fieldId)
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
      // A style image dropped with the old style (a basemap change) comes back
      m.on('styleimagemissing', () => addGlyphImages(m))
      // Over a system, field, plot or group: say what it is beside the pointer, and point at what
      // a click would select
      m.on('mousemove', (event) => {
        const text = hoverLabel(m, event.point)
        hover = text ? { x: event.point.x, y: event.point.y, text } : null
        m.getCanvas().style.cursor = text && !text.startsWith('Group:') ? 'pointer' : ''
      })
      m.on('mouseout', () => (hover = null))
      m.on('movestart', () => (hover = null))
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
          setSystemColors(m, readPalette())
          if (!m.getLayer(FIELD_LAYER)) return
          m.setPaintProperty(FIELD_LAYER, 'fill-color', color)
          m.setPaintProperty('fields-line', 'line-color', ['case', ['get', 'selected'], '#ffffff', color])
          m.setPaintProperty(PIN_LAYER, 'circle-color', color)
        }),
      )
    })

    return () => {
      disposed = true
      cleanups.forEach((cleanup) => cleanup())
      for (const { component } of [...markers.values(), ...plotMarkers.values()]) unmount(component)
      markers.clear()
      plotMarkers.clear()
      map?.remove()
    }
  })
</script>

<div
  bind:this={wrapper}
  class="group/map relative h-full w-full overflow-hidden bg-surface"
  data-far={zoom < FAR_ZOOM ? '' : undefined}
  data-mid={zoom >= FAR_ZOOM && zoom < NAME_ZOOM ? '' : undefined}
  data-plots={zoom >= NAME_ZOOM && zoom < SPREAD_ZOOM ? '' : undefined}
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

  {#if hover}
    <!-- Pointer users only: the list and the markers name everything for keyboards and screen readers -->
    <div
      class="pointer-events-none absolute z-10 max-w-64 -translate-x-1/2 -translate-y-full truncate rounded-md
        bg-surface-raised px-2 py-1 text-xs font-medium text-ink shadow-md ring-1 ring-line"
      style:left="{hover.x}px"
      style:top="{hover.y - 12}px"
      aria-hidden="true"
    >
      {hover.text}
    </div>
  {/if}

  {@render children?.()}
</div>
