<script lang="ts">
  import 'maplibre-gl/dist/maplibre-gl.css'

  import { onMount } from 'svelte'
  import type { GeoJSONSource, Map as MapLibreMap, Marker } from 'maplibre-gl'

  import { GEOCODER_ATTRIBUTION } from '@/lib/geocode'
  import {
    DEFAULT_RADIUS_FT,
    destination,
    distanceM,
    edgePointer,
    FEET_PER_METER,
    pivotRing,
    type LngLat,
  } from '@/lib/geo'
  import { basemapStyle, LABEL_FONT, setBasemap, type Basemap } from '@/lib/map/basemaps'
  import BasemapToggle from '@/lib/map/BasemapToggle.svelte'
  import { loadMapLibre } from '@/lib/map/maplibre'
  import PlaceSearch from '@/lib/map/PlaceSearch.svelte'
  import { type Bounds, fetchSoilAreas, SOIL_COLORS, type SoilAreas } from '@/lib/soils'

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
    soilTypes = [],
    height = '24rem',
  }: {
    latitude?: number | null
    longitude?: number | null
    radiusFt?: number | null
    arcStart?: number | null
    arcEnd?: number | null
    others?: Outline[]
    /** Names for the soil types layer */
    soilTypes?: { key: string; name: string }[]
    height?: string
  } = $props()

  // Wisconsin's Central Sands, where most WISP pivots are
  const DEFAULT_VIEW = { center: [-89.5, 44.25] as LngLat, zoom: 8 }
  const PIVOT_ZOOM = 14

  // Our sources, carried over when the basemap changes
  const OWN_SOURCES = ['others', 'pivot', 'soil-types']
  // Soil types are shown around the pivot, or in the view once zoomed in this far without one
  const SOIL_ZOOM = 13
  const SOIL_MARGIN_M = 900

  let container: HTMLDivElement
  let map: MapLibreMap | undefined = $state()
  let centerMarker: Marker | undefined
  let edgeMarker: Marker | undefined
  let basemap = $state<Basemap>('imagery')
  let soils = $state(false)
  let soilStatus = $state<'loading' | 'ready' | 'error' | 'zoom'>('zoom')
  let soilKeys = $state<string[]>([])
  let soilHover = $state<{ x: number; y: number; type: string; unit: string } | null>(null)
  let soilBox: Bounds | null = null
  let soilRequest: AbortController | undefined
  let locating = $state(false)
  let locateError = $state<string | null>(null)
  let pointer = $state<{ x: number; y: number; angle: number } | null>(null)
  let placeSearch: PlaceSearch | undefined = $state()

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
      layout: { 'text-field': ['get', 'name'], 'text-size': 12, 'text-font': LABEL_FONT },
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

  // Soil types around the pivot (PLAN.md Phase 7 F): the survey's map units colored and labeled by
  // the WISP soil type their surface texture suggests, loaded for an area around the pivot (or the
  // view, zoomed in, before it's placed) and again when the pivot moves out of it
  const soilName = (key: string | null) =>
    key ? (soilTypes.find((type) => type.key === key)?.name ?? key.replace(/_/g, ' ')) : 'No soil type'

  function soilArea(): Bounds | null {
    if (center) {
      const margin = radiusM + SOIL_MARGIN_M
      const [west, south] = destination(destination(center, margin, 270), margin, 180)
      const [east, north] = destination(destination(center, margin, 90), margin, 0)
      return [west, south, east, north]
    }
    if (!map || map.getZoom() < SOIL_ZOOM) return null
    const view = map.getBounds()
    return [view.getWest(), view.getSouth(), view.getEast(), view.getNorth()]
  }

  const covers = ([west, south, east, north]: Bounds, area: Bounds) =>
    area[0] >= west && area[1] >= south && area[2] <= east && area[3] <= north

  function loadSoils() {
    if (!map || !soils) return
    const area = soilArea()
    if (!area) {
      soilStatus = soilBox ? soilStatus : 'zoom'
      return
    }
    if (soilBox && covers(soilBox, area)) return
    soilRequest?.abort()
    const request = (soilRequest = new AbortController())
    soilStatus = 'loading'
    fetchSoilAreas(area, request.signal)
      .then((areas) => {
        if (request !== soilRequest || !map) return
        soilBox = area
        showSoilAreas(map, areas)
        soilKeys = [...new Set(areas.features.map((f) => f.properties.key).filter((key) => key !== null))]
        soilStatus = 'ready'
      })
      .catch((error: Error) => {
        if (error.name !== 'AbortError' && request === soilRequest) soilStatus = 'error'
      })
  }

  function showSoilAreas(m: MapLibreMap, areas: SoilAreas) {
    const data = {
      ...areas,
      features: areas.features.map((f) => ({
        ...f,
        properties: { ...f.properties, name: soilName(f.properties.key) },
      })),
    }
    const source = m.getSource<GeoJSONSource>('soil-types')
    if (source) return source.setData(data as never)
    m.addSource('soil-types', {
      type: 'geojson',
      data: data as never,
      attribution: 'Soils: <a href="https://websoilsurvey.nrcs.usda.gov/">USDA NRCS</a>',
    })
    const color = ['match', ['get', 'key'], ...Object.entries(SOIL_COLORS).flat(), '#9ca3af']
    const below = m.getLayer('others-line') ? 'others-line' : undefined
    m.addLayer(
      {
        id: 'soil-types-fill',
        type: 'fill',
        source: 'soil-types',
        paint: { 'fill-color': color as never, 'fill-opacity': 0.55 },
      },
      below,
    )
    m.addLayer(
      {
        id: 'soil-types-line',
        type: 'line',
        source: 'soil-types',
        paint: { 'line-color': '#ffffff', 'line-width': 0.8, 'line-opacity': 0.7 },
      },
      below,
    )
    m.addLayer(
      {
        id: 'soil-types-label',
        type: 'symbol',
        source: 'soil-types',
        minzoom: 14,
        layout: { 'text-field': ['get', 'name'], 'text-size': 11, 'text-font': LABEL_FONT },
        paint: { 'text-color': '#ffffff', 'text-halo-color': '#000000', 'text-halo-width': 1.2 },
      },
      below,
    )
  }

  function hideSoilAreas() {
    soilRequest?.abort()
    soilBox = null
    soilHover = null
    for (const layer of ['soil-types-label', 'soil-types-line', 'soil-types-fill']) {
      if (map?.getLayer(layer)) map.removeLayer(layer)
    }
    if (map?.getSource('soil-types')) map.removeSource('soil-types')
  }

  function toggleSoils() {
    soils = !soils
    if (soils) loadSoils()
    else hideSoilAreas()
  }

  // Load again when the pivot moves out of the loaded area
  $effect(() => {
    void [center, radiusM]
    if (soils) loadSoils()
  })

  async function switchBase(to: Basemap) {
    if (!map) return
    basemap = to
    await setBasemap(map, to, (id) => OWN_SOURCES.includes(id))
    drawPivot()
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

  onMount(() => {
    let disposed = false
    loadMapLibre().then(({ Map, NavigationControl, LngLatBounds, AttributionControl }) => {
      if (disposed) return
      const m = new Map({ container, style: basemapStyle(basemap), ...DEFAULT_VIEW, attributionControl: false })
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
      m.on('moveend', loadSoils)
      m.on('mousemove', 'soil-types-fill', (event) => {
        const feature = event.features?.[0]
        if (!feature) return
        soilHover = {
          x: event.point.x,
          y: event.point.y,
          type: String(feature.properties.name),
          unit: String(feature.properties.unit),
        }
      })
      m.on('mouseleave', 'soil-types-fill', () => (soilHover = null))
      m.on('move', updatePointer)
      m.on('resize', updatePointer)
      m.on('click', (event) => {
        placeSearch?.close()
        // A click away from the pivot moves it; clicks on the markers are drags
        if (!center || distanceM(center, [event.lngLat.lng, event.lngLat.lat]) > radiusM * 0.15) {
          setCenter([event.lngLat.lng, event.lngLat.lat])
        }
      })
      map = m
    })
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

    <div class="absolute top-2 left-2">
      <div class="flex gap-2">
        <BasemapToggle value={basemap} onchange={switchBase} />
        <button
          type="button"
          class="rounded-md border border-line px-2.5 py-1.5 text-xs shadow
            {soils ? 'bg-brand-600 text-white dark:text-surface' : 'bg-surface-raised hover:bg-surface'}"
          aria-pressed={soils}
          title="WISP's soil types from the USDA soil survey"
          onclick={toggleSoils}>Soil types</button
        >
      </div>
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

    {#if soilHover}
      <div
        class="pointer-events-none absolute z-10 max-w-60 rounded-md border border-line bg-surface-raised px-2.5 py-1.5
          text-xs shadow-lg"
        style:left="{soilHover.x + 14}px"
        style:top="{soilHover.y + 14}px"
      >
        <p class="font-medium">{soilHover.type}</p>
        <p class="text-ink-muted">{soilHover.unit}</p>
      </div>
    {/if}

    <div class="absolute bottom-2 left-2 w-[min(18rem,calc(100%-6rem))]">
      <PlaceSearch bind:this={placeSearch} {map} maxZoom={PIVOT_ZOOM - 1} />
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
  {#if soils}
    <div class="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs" aria-live="polite">
      <span class="font-medium">Soil types:</span>
      {#if soilStatus === 'loading'}
        <span class="text-ink-muted">loading from the soil survey…</span>
      {:else if soilStatus === 'error'}
        <span class="text-ink-muted">the soil survey isn't answering right now.</span>
      {:else if soilStatus === 'zoom'}
        <span class="text-ink-muted">place the pivot, or zoom in, to see them.</span>
      {:else}
        {#each soilTypes.filter((type) => soilKeys.includes(type.key)) as type (type.key)}
          <span class="flex items-center gap-1"
            ><span class="size-3 rounded-sm border border-line" style:background={SOIL_COLORS[type.key]}
            ></span>{type.name}</span
          >
        {:else}
          <span class="text-ink-muted">none matched here.</span>
        {/each}
        <span class="text-ink-muted"
          >From each map unit's main soil in the <a
            href="https://websoilsurvey.nrcs.usda.gov/"
            target="_blank"
            rel="noopener"
            class="text-brand-600 hover:underline">USDA soil survey</a
          >.</span
        >
      {/if}
    </div>
  {/if}
</div>
