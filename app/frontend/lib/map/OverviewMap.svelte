<script module lang="ts">
  /** Our sources (pivots, and overlays named overlay-*), carried over when the basemap changes */
  export const isOwnSource = (id: string) => id === 'pivots' || id.startsWith('overlay-')
  /** Overlays go under the pivots */
  export const PIVOT_LAYER = 'pivots-fill'
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

  import { basemapStyle, type Basemap, setBasemap } from './basemaps'
  import BasemapToggle from './BasemapToggle.svelte'
  import { ButtonControl, FIT_ICON } from './controls'
  import { loadMapLibre } from './maplibre'
  import PivotMarker from './PivotMarker.svelte'
  import { type MapPivot, pivotBounds, pivotFeatures } from './pivots'
  import PlaceSearch from './PlaceSearch.svelte'

  // The operation's pivots on a map (PLAN.md Phase 7): each drawn to scale in its most urgent
  // field's status color, with a marker of its fields' badges at the center. Clicking a pivot selects
  // it; the page shows its details in the panel (children) and the toolbar adds to the top-left.
  let {
    pivots,
    selectedId,
    highlighted,
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
    selectedId: number | null
    /** The pivots in the "needs water within" window (others are dimmed), or null for none */
    highlighted: Set<number> | null
    basemap: Basemap
    /** Where to start; without one the map fits every pivot */
    view: { center: LngLat; zoom: number } | null
    unitSystem?: UnitSystem
    onselect: (pivotId: number | null) => void
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

  function statusColor(): ExpressionSpecification {
    const { status } = readPalette()
    return [
      'match',
      ['get', 'status'],
      'irrigate',
      status.irrigate,
      'caution',
      status.caution,
      'ok',
      status.ok,
      'full',
      status.full,
      '#9ca3af',
    ]
  }

  function addPivotLayers(m: MapLibreMap) {
    m.addSource('pivots', { type: 'geojson', data: features() })
    const color = statusColor()
    m.addLayer({
      id: PIVOT_LAYER,
      type: 'fill',
      source: 'pivots',
      paint: {
        'fill-color': color,
        'fill-opacity': ['case', ['get', 'dimmed'], 0.05, ['get', 'selected'], 0.4, 0.22],
      },
    })
    // A white casing under the status line keeps it visible on imagery
    m.addLayer({
      id: 'pivots-casing',
      type: 'line',
      source: 'pivots',
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
      paint: {
        'line-color': color,
        'line-width': ['case', ['get', 'selected'], 3.5, 2],
        'line-opacity': ['case', ['get', 'dimmed'], 0.35, 1],
      },
    })
  }

  async function syncMarkers() {
    const m = map
    if (!m) return
    const { Marker } = await loadMapLibre()
    const ids = new Set(pivots.map((pivot) => pivot.id))
    for (const [id, entry] of markers) {
      if (ids.has(id)) continue
      entry.marker.remove()
      unmount(entry.component)
      markers.delete(id)
    }
    for (const pivot of pivots) {
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
    void [pivots, selectedId, highlighted]
    map?.getSource<GeoJSONSource>('pivots')?.setData(features())
    syncMarkers()
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
    onload?.(map)
  }

  function onClick(event: MapMouseEvent) {
    placeSearch?.close()
    const hit = map?.queryRenderedFeatures(event.point, { layers: [PIVOT_LAYER] })[0]
    onselect(hit ? Number(hit.properties.id) : null)
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
      m.addControl(new ButtonControl('Fit all pivots', FIT_ICON, () => fit()), 'top-right')
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
      m.on('mouseenter', PIVOT_LAYER, () => (m.getCanvas().style.cursor = 'pointer'))
      m.on('mouseleave', PIVOT_LAYER, () => (m.getCanvas().style.cursor = ''))
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
