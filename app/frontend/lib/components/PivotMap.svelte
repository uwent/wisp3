<script lang="ts">
  import 'maplibre-gl/dist/maplibre-gl.css'

  import { onMount } from 'svelte'
  import type { GeoJSONSource, LayerSpecification, Map as MapLibreMap, Marker, StyleSpecification } from 'maplibre-gl'

  import { GEOCODER_ATTRIBUTION, searchPlaces, type Place } from '@/lib/geocode'
  import {
    DEFAULT_RADIUS_FT,
    destination,
    distanceM,
    edgePointer,
    FEET_PER_METER,
    pivotRing,
    type LngLat,
  } from '@/lib/geo'

  type Outline = {
    id: number
    name: string
    latitude: number
    longitude: number
    radius_ft: number | null
    arc_start_deg: number | null
    arc_end_deg: number | null
  }

  // The pivot location picker (PLAN.md §4): click the map to place the pivot's center, drag the
  // center or the edge handle to adjust it. The group's other pivots are drawn for reference. A
  // place search moves the map (it doesn't place the pivot), and an arrow at the edge points back
  // to the pivot when it's out of view.
  let {
    latitude = $bindable(null),
    longitude = $bindable(null),
    radiusFt = $bindable(null),
    arcStart = null,
    arcEnd = null,
    others = [],
    height = '24rem',
  }: {
    latitude?: number | null
    longitude?: number | null
    radiusFt?: number | null
    arcStart?: number | null
    arcEnd?: number | null
    others?: Outline[]
    height?: string
  } = $props()

  // Wisconsin's Central Sands, where most WISP pivots are
  const DEFAULT_VIEW = { center: [-89.5, 44.25] as LngLat, zoom: 8 }
  const PIVOT_ZOOM = 14

  // USGS National Map imagery with roads, boundaries and place names (public domain), or
  // OpenFreeMap streets
  const IMAGERY: StyleSpecification = {
    version: 8,
    glyphs: 'https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf',
    sources: {
      imagery: {
        type: 'raster',
        tiles: ['https://basemap.nationalmap.gov/arcgis/rest/services/USGSImageryTopo/MapServer/tile/{z}/{y}/{x}'],
        tileSize: 256,
        maxzoom: 16,
        attribution:
          'Imagery: <a href="https://www.usgs.gov/programs/national-geospatial-program/national-map">USGS</a>',
      },
    },
    layers: [{ id: 'imagery', type: 'raster', source: 'imagery' }],
  }
  const STREETS = 'https://tiles.openfreemap.org/styles/liberty'
  // Our sources and layers, carried over when the basemap changes
  const OWN_SOURCES = ['others', 'pivot']

  let container: HTMLDivElement
  let map: MapLibreMap | undefined = $state()
  let centerMarker: Marker | undefined
  let edgeMarker: Marker | undefined
  let baseLayer = $state<'imagery' | 'streets'>('imagery')
  let locating = $state(false)
  let locateError = $state<string | null>(null)
  let pointer = $state<{ x: number; y: number; angle: number } | null>(null)

  let query = $state('')
  let searching = $state(false)
  let places = $state<Place[] | null>(null)
  let searchError = $state<string | null>(null)

  const center = $derived<LngLat | null>(latitude !== null && longitude !== null ? [longitude, latitude] : null)
  const radiusM = $derived((radiusFt ?? DEFAULT_RADIUS_FT) / FEET_PER_METER)
  // The edge handle sits on the arc's middle bearing, or due east for a full circle
  const handleBearing = $derived(
    arcStart !== null && arcEnd !== null ? arcStart + ((((arcEnd - arcStart) % 360) + 360) % 360 || 360) / 2 : 90,
  )

  const round = (value: number) => Math.round(value * 1e6) / 1e6

  function setCenter([lng, lat]: LngLat) {
    longitude = round(lng)
    latitude = round(lat)
    radiusFt ??= DEFAULT_RADIUS_FT
  }

  function feature(ring: LngLat[], name = '') {
    return {
      type: 'Feature' as const,
      properties: { name },
      geometry: { type: 'Polygon' as const, coordinates: [ring] },
    }
  }

  function addLayers(m: MapLibreMap) {
    m.addSource('others', {
      type: 'geojson',
      data: {
        type: 'FeatureCollection',
        features: others.map((other) =>
          feature(
            pivotRing(
              [other.longitude, other.latitude],
              other.radius_ft ?? DEFAULT_RADIUS_FT,
              other.arc_start_deg,
              other.arc_end_deg,
            ),
            other.name,
          ),
        ),
      },
    })
    m.addLayer({
      id: 'others-line',
      type: 'line',
      source: 'others',
      paint: { 'line-color': '#ffffff', 'line-width': 1.5, 'line-opacity': 0.7 },
    })
    m.addLayer({
      id: 'others-label',
      type: 'symbol',
      source: 'others',
      layout: { 'text-field': ['get', 'name'], 'text-size': 12, 'text-font': ['Noto Sans Regular'] },
      paint: { 'text-color': '#ffffff', 'text-halo-color': '#000000', 'text-halo-width': 1 },
    })
    m.addSource('pivot', { type: 'geojson', data: { type: 'FeatureCollection', features: [] } })
    m.addLayer({
      id: 'pivot-fill',
      type: 'fill',
      source: 'pivot',
      paint: { 'fill-color': '#3987e5', 'fill-opacity': 0.25 },
    })
    m.addLayer({
      id: 'pivot-line',
      type: 'line',
      source: 'pivot',
      paint: { 'line-color': '#3987e5', 'line-width': 2.5 },
    })
    drawPivot()
  }

  function drawPivot() {
    const source = map?.getSource<GeoJSONSource>('pivot')
    if (!map || !source) return
    source.setData({
      type: 'FeatureCollection',
      features: center ? [feature(pivotRing(center, radiusFt ?? DEFAULT_RADIUS_FT, arcStart, arcEnd))] : [],
    })
  }

  async function placeMarkers() {
    if (!map) return
    const { Marker } = await import('maplibre-gl')
    if (!center) {
      centerMarker?.remove()
      edgeMarker?.remove()
      centerMarker = edgeMarker = undefined
      return
    }
    if (!centerMarker) {
      centerMarker = new Marker({ draggable: true, color: '#1c5cab' }).setLngLat(center).addTo(map)
      centerMarker.on('drag', () => {
        const { lng, lat } = centerMarker!.getLngLat()
        setCenter([lng, lat])
      })
      const handle = document.createElement('div')
      handle.className = 'size-4 rounded-full border-2 border-white bg-[#1c5cab] shadow cursor-ew-resize'
      handle.title = 'Drag to set the radius'
      edgeMarker = new Marker({ element: handle, draggable: true })
        .setLngLat(destination(center, radiusM, handleBearing))
        .addTo(map)
      edgeMarker.on('drag', () => {
        if (!center) return
        const { lng, lat } = edgeMarker!.getLngLat()
        radiusFt = Math.max(50, Math.round(distanceM(center, [lng, lat]) * FEET_PER_METER))
      })
      edgeMarker.on('dragend', () => {
        if (center) edgeMarker?.setLngLat(destination(center, radiusM, handleBearing))
      })
    } else {
      centerMarker.setLngLat(center)
      edgeMarker?.setLngLat(destination(center, radiusM, handleBearing))
    }
  }

  // An arrow at the map's edge when the pivot is placed but scrolled out of view
  function updatePointer() {
    if (!map || !center) return (pointer = null)
    const point = map.project(center)
    pointer = edgePointer(point, container.clientWidth, container.clientHeight, 28)
  }

  // Redraw when the center, radius or arc change, whether from the map or the form's inputs
  $effect(() => {
    void [center, radiusFt, arcStart, arcEnd, handleBearing]
    drawPivot()
    placeMarkers()
    updatePointer()
  })

  // A new basemap style replaces every source and layer, so ours are copied into it
  function switchBase(to: 'imagery' | 'streets') {
    if (!map || baseLayer === to) return
    baseLayer = to
    map.setStyle(to === 'imagery' ? IMAGERY : STREETS, {
      transformStyle: (previous, next) => ({
        ...next,
        sources: { ...next.sources, ...Object.fromEntries(OWN_SOURCES.map((id) => [id, previous!.sources[id]])) },
        layers: [
          ...next.layers,
          ...previous!.layers.filter(
            (layer: LayerSpecification) => 'source' in layer && OWN_SOURCES.includes(layer.source as string),
          ),
        ],
      }),
    })
    map.once('idle', drawPivot)
  }

  function showPivot() {
    if (center) map?.flyTo({ center, zoom: Math.max(map.getZoom(), PIVOT_ZOOM - 1) })
  }

  function locate() {
    if (!navigator.geolocation) return (locateError = 'Location is not available in this browser')
    locating = true
    locateError = null
    navigator.geolocation.getCurrentPosition(
      ({ coords }) => {
        locating = false
        setCenter([coords.longitude, coords.latitude])
        map?.flyTo({ center: [coords.longitude, coords.latitude], zoom: PIVOT_ZOOM })
      },
      () => {
        locating = false
        locateError = 'Could not get your location'
      },
      { enableHighAccuracy: true, timeout: 10_000 },
    )
  }

  async function search() {
    if (!query.trim() || searching) return
    searching = true
    searchError = null
    places = null
    try {
      const view = map?.getBounds()
      const found = await searchPlaces(
        query.trim(),
        view && [view.getWest(), view.getSouth(), view.getEast(), view.getNorth()],
      )
      if (found.length === 0) searchError = 'No places found'
      else if (found.length === 1) goTo(found[0])
      else places = found
    } catch {
      searchError = 'Search is unavailable right now'
    } finally {
      searching = false
    }
  }

  // Moves the map to a place; it doesn't place the pivot
  function goTo(place: Place) {
    places = null
    const [west, south, east, north] = place.bounds
    map?.fitBounds(
      [
        [west, south],
        [east, north],
      ],
      { padding: 40, maxZoom: PIVOT_ZOOM - 1 },
    )
  }

  // The search box sits inside the page's form: Enter searches instead of submitting it
  function onSearchKey(event: KeyboardEvent) {
    if (event.key === 'Enter') {
      event.preventDefault()
      search()
    } else if (event.key === 'Escape') {
      places = null
    }
  }

  onMount(() => {
    let disposed = false
    // MapLibre computes its worker's URL at run time, which Vite can't follow, so Vite bundles the
    // worker itself and MapLibre is told where it is
    Promise.all([import('maplibre-gl'), import('maplibre-gl/dist/maplibre-gl-worker.mjs?worker&url')]).then(
      ([maplibre, worker]) => {
        if (disposed) return
        const { Map, NavigationControl, LngLatBounds, AttributionControl } = maplibre
        maplibre.setWorkerUrl(worker.default)
        const m = new Map({ container, style: IMAGERY, ...DEFAULT_VIEW, attributionControl: false })
        m.addControl(new AttributionControl({ compact: true, customAttribution: GEOCODER_ATTRIBUTION }), 'bottom-right')
        m.addControl(new NavigationControl({ showCompass: false }), 'top-right')
        if (center) {
          m.jumpTo({ center, zoom: PIVOT_ZOOM })
        } else if (others.length) {
          const bounds = new LngLatBounds()
          others.forEach((other) => bounds.extend([other.longitude, other.latitude]))
          m.fitBounds(bounds, { padding: 80, maxZoom: PIVOT_ZOOM - 1, duration: 0 })
        }
        m.on('load', () => {
          addLayers(m)
          placeMarkers()
        })
        m.on('move', updatePointer)
        m.on('resize', updatePointer)
        m.on('click', (event) => {
          places = null
          // A click away from the pivot moves it; clicks on the markers are drags
          if (!center || distanceM(center, [event.lngLat.lng, event.lngLat.lat]) > radiusM * 0.15) {
            setCenter([event.lngLat.lng, event.lngLat.lat])
          }
        })
        map = m
      },
    )
    return () => {
      disposed = true
      map?.remove()
    }
  })
</script>

<div class="space-y-2">
  <div class="relative overflow-hidden rounded-lg border border-line" style:height>
    <div
      bind:this={container}
      class="h-full w-full"
      aria-label="Map: click to place the pivot center"
      role="application"
    ></div>

    <div
      class="absolute top-2 left-2 flex overflow-hidden rounded-md border border-line bg-surface-raised text-xs shadow"
    >
      {#each [['imagery', 'Satellite'], ['streets', 'Map']] as const as [key, name] (key)}
        <button
          type="button"
          class="px-2.5 py-1.5 {baseLayer === key ? 'bg-brand-600 text-white dark:text-surface' : 'hover:bg-surface'}"
          aria-pressed={baseLayer === key}
          onclick={() => switchBase(key)}>{name}</button
        >
      {/each}
    </div>

    {#if !center}
      <p
        class="pointer-events-none absolute top-12 right-12 left-2 mx-auto max-w-xs rounded-md bg-black/60 px-3 py-2 text-center text-sm text-white"
      >
        Click the map at the center of the pivot
      </p>
    {/if}

    {#if pointer}
      <button
        type="button"
        class="absolute flex size-9 -translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-full border-2 border-white bg-[#1c5cab] text-white shadow-lg hover:scale-110"
        style:left="{pointer.x}px"
        style:top="{pointer.y}px"
        aria-label="The pivot is off the map: show it"
        title="Show the pivot"
        onclick={showPivot}
      >
        <svg
          viewBox="0 0 24 24"
          class="size-5"
          style:transform="rotate({pointer.angle}deg)"
          fill="none"
          stroke="currentColor"
          stroke-width="2.5"
          stroke-linecap="round"
          stroke-linejoin="round"
          aria-hidden="true"
        >
          <path d="M5 12h14M13 6l6 6-6 6" />
        </svg>
      </button>
    {/if}

    <div class="absolute bottom-2 left-2 w-[min(18rem,calc(100%-6rem))]">
      {#if places}
        <ul
          class="mb-1 overflow-hidden rounded-md border border-line bg-surface-raised text-sm shadow-lg"
          aria-label="Places found"
        >
          {#each places as place (place.label)}
            <li>
              <button
                type="button"
                class="block w-full px-3 py-2 text-left hover:bg-brand-50"
                onclick={() => goTo(place)}>{place.label}</button
              >
            </li>
          {/each}
        </ul>
      {/if}
      {#if searchError}
        <p class="mb-1 rounded-md bg-surface-raised px-3 py-1.5 text-xs text-status-irrigate shadow">{searchError}</p>
      {/if}
      <div class="flex overflow-hidden rounded-md border border-line bg-surface-raised shadow">
        <input
          type="search"
          bind:value={query}
          onkeydown={onSearchKey}
          placeholder="Find a place, e.g. Hancock WI"
          aria-label="Find a place on the map"
          class="min-w-0 flex-1 border-0 px-3 py-1.5 text-sm focus:ring-0"
        />
        <button
          type="button"
          class="px-3 text-sm text-brand-600 hover:bg-brand-50 disabled:opacity-60"
          onclick={search}
          disabled={searching}
        >
          {searching ? '…' : 'Go'}
        </button>
      </div>
    </div>
  </div>
  <div class="flex flex-wrap items-center gap-3 text-sm">
    <button
      type="button"
      class="text-brand-600 hover:underline disabled:opacity-60"
      onclick={locate}
      disabled={locating}
    >
      {locating ? 'Finding you…' : 'Use my location'}
    </button>
    {#if locateError}<span class="text-status-irrigate">{locateError}</span>{/if}
    {#if center}<span class="text-ink-muted"
        >Drag the pin to move the pivot, or the round handle to set its radius.</span
      >{/if}
  </div>
</div>
