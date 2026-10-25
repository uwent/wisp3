<script lang="ts">
  import 'maplibre-gl/dist/maplibre-gl.css'

  import { onMount } from 'svelte'
  import type { GeoJSONSource, Map as MapLibreMap, Marker as MarkerClass } from 'maplibre-gl'

  import { GEOCODER_ATTRIBUTION } from '@/lib/geocode'
  import {
    bearing,
    DEFAULT_RADIUS_FT,
    destination,
    distanceM,
    draftShape,
    edgePointer,
    FEET_PER_METER,
    MAX_RADIUS_FT,
    MIN_SIZE_FT,
    pivotOutline,
    linearCorners,
    linearOf,
    offset,
    resizeLinear,
    snapBearing,
    sweep,
    travelArrow,
    type LngLat,
    type PivotShape,
    type ShapeDraft,
  } from '@/lib/geo'
  import { basemapStyle, LABEL_FONT, setBasemap, type Basemap } from '@/lib/map/basemaps'
  import BasemapToggle from '@/lib/map/BasemapToggle.svelte'
  import { resizeCursor, ROTATE_CURSOR } from '@/lib/map/cursors'
  import { loadMapLibre } from '@/lib/map/maplibre'
  import PlaceSearch from '@/lib/map/PlaceSearch.svelte'
  import { type Bounds, fetchSoilAreas, SOIL_COLORS, type SoilAreas } from '@/lib/soils'

  type Outline = PivotShape & { id: number; name: string }

  // The pivot location picker (PLAN.md §4): click the map to place the pivot's center, drag the
  // center or the handles to adjust it. A center pivot has a handle on its edge for the radius and,
  // for a partial circle, one at each end of the arc; a linear move has handles on two opposite
  // corners (its front left and back right, facing its direction of travel) and one past its front
  // end that turns it. The group's other pivots are drawn for reference. A place search moves
  // the map (it doesn't place the pivot), and an arrow at the edge points back to the pivot when
  // it's out of view.
  let {
    shape = $bindable(),
    others = [],
    soilTypes = [],
    height = '24rem',
  }: {
    shape: ShapeDraft
    others?: Outline[]
    /** Names for the soil types layer */
    soilTypes?: { key: string; name: string }[]
    height?: string
  } = $props()

  // Wisconsin's Central Sands, where most WISP pivots are
  const DEFAULT_VIEW = { center: [-89.5, 44.25] as LngLat, zoom: 8 }
  const PIVOT_ZOOM = 14
  // The least an arc can sweep with its handles
  const MIN_SWEEP_DEG = 5

  // Our sources, carried over when the basemap changes
  const OWN_SOURCES = ['others', 'pivot', 'soil-types']
  // Soil types are shown around the pivot, or in the view once zoomed in this far without one
  const SOIL_ZOOM = 13
  const SOIL_MARGIN_M = 900

  type Handle = 'radius' | 'start' | 'end' | 'frontLeft' | 'backRight' | 'rotate'

  let container: HTMLDivElement
  let map: MapLibreMap | undefined = $state()
  let Marker: typeof MarkerClass | undefined
  let centerMarker: MarkerClass | undefined
  let handles: Partial<Record<Handle, MarkerClass>> = {}
  let handleSet = ''
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

  const linear = $derived(shape.kind === 'linear')
  const outline = $derived(draftShape(shape))
  const center = $derived<LngLat | null>(outline && [outline.longitude, outline.latitude])
  const radiusM = $derived((shape.radiusFt ?? DEFAULT_RADIUS_FT) / FEET_PER_METER)
  const machine = $derived(
    linearOf({ length_ft: shape.lengthFt, travel_ft: shape.travelFt, travel_bearing_deg: shape.travelBearing }),
  )
  // How far the pivot reaches from its center
  const reachM = $derived(linear ? Math.hypot(machine.lengthFt, machine.travelFt) / 2 / FEET_PER_METER : radiusM)
  // The turning handle sits past the end of the linear nearer where it was last dragged
  let rotateBack = $state(false)
  const rotatePosition = $derived.by(() => {
    if (!center) return null
    const travelM = machine.travelFt / FEET_PER_METER
    return offset(center, travelM / 2 + Math.max(travelM * 0.1, 40), 0, machine.bearingDeg + (rotateBack ? 180 : 0))
  })
  const arc = $derived(outline?.arc_start_deg != null && outline.arc_end_deg != null)
  // The radius handle sits on the arc's middle bearing, or due east for a full circle
  const handleBearing = $derived(arc ? shape.arcStart! + sweep(shape.arcStart, shape.arcEnd) / 2 : 90)

  const round = (value: number) => Math.round(value * 1e6) / 1e6

  function setCenter([lng, lat]: LngLat) {
    shape.longitude = round(lng)
    shape.latitude = round(lat)
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
        features: others.map((other) => feature(pivotOutline(other), other.name)),
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
      paint: { 'line-color': '#3987e5', 'line-width': ['match', ['get', 'role'], 'arrow', 2, 2.5] },
      layout: { 'line-cap': 'round', 'line-join': 'round' },
    })
    drawPivot()
  }

  function drawPivot() {
    const source = map?.getSource<GeoJSONSource>('pivot')
    if (!map || !source) return
    const line = (coordinates: LngLat[], role: string) => ({
      type: 'Feature' as const,
      properties: { role },
      geometry: { type: 'LineString' as const, coordinates },
    })
    // A linear's turning handle hangs on a line from the middle of its end, and an arrow along its
    // travel shows which way it runs
    const extras =
      linear && center && rotatePosition
        ? [
            line(
              [
                offset(center, machine.travelFt / FEET_PER_METER / 2, 0, machine.bearingDeg + (rotateBack ? 180 : 0)),
                rotatePosition,
              ],
              'stalk',
            ),
            ...travelArrow(center, machine).map((part) => line(part, 'arrow')),
          ]
        : []
    source.setData({
      type: 'FeatureCollection',
      features: outline ? [feature(pivotOutline(outline)), ...extras] : [],
    })
  }

  // Where each of the shape's handles goes
  function handlePositions(): Partial<Record<Handle, LngLat>> {
    if (!center) return {}
    if (linear) {
      const [frontLeft, , backRight] = linearCorners(center, machine)
      return { frontLeft, backRight, rotate: rotatePosition! }
    }
    const positions: Partial<Record<Handle, LngLat>> = { radius: destination(center, radiusM, handleBearing) }
    if (arc) {
      positions.start = destination(center, radiusM, shape.arcStart!)
      positions.end = destination(center, radiusM, shape.arcEnd!)
    }
    return positions
  }

  const HANDLE_STYLE: Record<Handle, { className: string; title: string }> = {
    radius: { className: 'rounded-full bg-[#1c5cab]', title: 'Drag to set the radius' },
    start: { className: 'rounded-full bg-white', title: 'Drag to set where the arc starts' },
    end: { className: 'rounded-full bg-white', title: 'Drag to set where the arc ends' },
    frontLeft: { className: 'rounded-sm bg-[#1c5cab]', title: 'Drag to resize the linear move' },
    backRight: { className: 'rounded-sm bg-[#1c5cab]', title: 'Drag to resize the linear move' },
    rotate: { className: 'rounded-full bg-white', title: 'Drag to turn the linear move' },
  }

  // Each handle's cursor: circling arrows for those that turn about the center, and a double arrow
  // along the drag for those that resize, turned with the map
  function handleCursor(name: Handle, position: LngLat): string {
    if (name === 'start' || name === 'end' || name === 'rotate') return ROTATE_CURSOR
    const along = name === 'radius' ? handleBearing : bearing(center!, position)
    return resizeCursor(along - (map?.getBearing() ?? 0))
  }

  // A handle was dragged to a point: change the shape to follow it
  function dragHandle(handle: Handle, point: LngLat, fixedCorner: LngLat | null) {
    if (!center) return
    if (handle === 'radius') {
      const feet = Math.round(distanceM(center, point) * FEET_PER_METER)
      shape.radiusFt = Math.min(MAX_RADIUS_FT, Math.max(MIN_SIZE_FT, feet))
    } else if (handle === 'start' || handle === 'end') {
      const angle = Math.round(bearing(center, point)) % 360
      const [start, end] = handle === 'start' ? [angle, shape.arcEnd] : [shape.arcStart, angle]
      const swept = sweep(start, end)
      if (swept < MIN_SWEEP_DEG || swept > 360 - MIN_SWEEP_DEG) return
      if (handle === 'start') shape.arcStart = angle
      else shape.arcEnd = angle
    } else if (handle === 'rotate') {
      // Whole degrees 0–179, snapped to north–south or east–west; the handle stays at the end it's
      // dragged around
      const raw = (bearing(center, point) + 360) % 360
      const snapped = snapBearing(raw)
      shape.travelBearing = snapped
      rotateBack = Math.abs(((raw - snapped + 540) % 360) - 180) > 90
    } else if (fixedCorner) {
      const resized = resizeLinear(fixedCorner, point, machine.bearingDeg, handle as 'frontLeft' | 'backRight')
      setCenter(resized.center)
      shape.lengthFt = Math.round(resized.lengthFt)
      shape.travelFt = Math.round(resized.travelFt)
    }
  }

  // Handles aren't MapLibre's draggable markers, which follow the pointer and would flicker between
  // it and the shape: a drag changes the shape, and the handle is only ever put where the shape puts it
  function followPointer(element: HTMLElement, name: Handle) {
    // A corner is dragged against the opposite one, where it was when the drag began
    let fixedCorner: LngLat | null = null
    // Keep the map from panning, or placing the pivot on the click that ends a drag
    const keep = (event: Event) => event.stopPropagation()
    element.addEventListener('mousedown', keep)
    element.addEventListener('touchstart', keep, { passive: true })
    element.addEventListener('click', keep)
    element.addEventListener('pointerdown', (event) => {
      if (event.button !== 0) return
      event.preventDefault()
      event.stopPropagation()
      element.setPointerCapture(event.pointerId)
      const opposite = { frontLeft: 'backRight', backRight: 'frontLeft' }[name as string] as Handle | undefined
      fixedCorner = (opposite && handlePositions()[opposite]) ?? null
    })
    element.addEventListener('pointermove', (event) => {
      if (!map || !element.hasPointerCapture(event.pointerId)) return
      const box = map.getCanvasContainer().getBoundingClientRect()
      const { lng, lat } = map.unproject([event.clientX - box.left, event.clientY - box.top])
      dragHandle(name, [lng, lat], fixedCorner)
    })
    const end = (event: PointerEvent) => {
      if (element.hasPointerCapture(event.pointerId)) element.releasePointerCapture(event.pointerId)
      fixedCorner = null
    }
    element.addEventListener('pointerup', end)
    element.addEventListener('pointercancel', end)
  }

  function placeMarkers() {
    if (!map || !Marker) return
    const positions = handlePositions()
    const set = Object.keys(positions).join(' ')
    if (set !== handleSet || !center) {
      Object.values(handles).forEach((marker) => marker.remove())
      handles = {}
      handleSet = ''
    }
    if (!center) {
      centerMarker?.remove()
      centerMarker = undefined
      return
    }
    if (!centerMarker) {
      centerMarker = new Marker({ draggable: true, color: '#1c5cab' }).setLngLat(center).addTo(map)
      centerMarker.on('drag', () => {
        const { lng, lat } = centerMarker!.getLngLat()
        setCenter([lng, lat])
      })
    } else {
      centerMarker.setLngLat(center)
    }
    for (const [name, position] of Object.entries(positions) as [Handle, LngLat][]) {
      const cursor = handleCursor(name, position)
      const existing = handles[name]
      if (existing) {
        existing.setLngLat(position)
        const element = existing.getElement()
        if (element.style.cursor !== cursor) element.style.cursor = cursor
        continue
      }
      const element = document.createElement('div')
      element.className = `size-4 touch-none border-2 border-white shadow ${HANDLE_STYLE[name].className}`
      if (name === 'start' || name === 'end' || name === 'rotate')
        element.classList.replace('border-white', 'border-[#1c5cab]')
      element.title = HANDLE_STYLE[name].title
      element.style.cursor = cursor
      followPointer(element, name)
      handles[name] = new Marker({ element }).setLngLat(position).addTo(map)
    }
    handleSet = set
  }

  // An arrow at the map's edge when the pivot is placed but scrolled out of view
  function updatePointer() {
    if (!map || !center) return (pointer = null)
    const point = map.project(center)
    pointer = edgePointer(point, container.clientWidth, container.clientHeight, 28)
  }

  // Redraw when the shape changes, whether from the map or the form's inputs
  $effect(() => {
    void [outline, handleBearing, rotatePosition]
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
      const margin = reachM + SOIL_MARGIN_M
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
    void [center, reachM]
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
    if (!navigator.geolocation)
      return (locateError = "This browser can't share your location. Click the map or search for a place instead.")
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
        locateError = "Couldn't get your location. Check that location sharing is allowed, or click the map instead."
      },
      { enableHighAccuracy: true, timeout: 10_000 },
    )
  }

  onMount(() => {
    let disposed = false
    loadMapLibre().then((maplibre) => {
      if (disposed) return
      const { Map, NavigationControl, LngLatBounds, AttributionControl } = maplibre
      Marker = maplibre.Marker
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
      m.on('rotate', placeMarkers)
      m.on('click', (event) => {
        placeSearch?.close()
        // A click away from the pivot moves it; clicks on the markers are drags. Placing it zooms in
        // to fit it, handles and all, so they're apart and in view.
        const point: LngLat = [event.lngLat.lng, event.lngLat.lat]
        if (!center) {
          setCenter(point)
          const bounds = new LngLatBounds()
          for (const corner of [...pivotOutline(draftShape(shape)!), ...Object.values(handlePositions())]) {
            bounds.extend(corner)
          }
          if (m.getZoom() < PIVOT_ZOOM - 1) m.fitBounds(bounds, { padding: 40, maxZoom: PIVOT_ZOOM, duration: 600 })
        } else if (distanceM(center, point) > reachM * 0.15) {
          setCenter(point)
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
      aria-label="Map: click to place the pivot, or enter its coordinates and size in the fields below"
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
          title="Shade the map by soil type, from the USDA soil survey"
          onclick={toggleSoils}>Soil types</button
        >
      </div>
    </div>

    {#if !center}
      <p
        class="pointer-events-none absolute top-12 right-12 left-2 mx-auto max-w-xs rounded-md bg-black/60 px-3 py-2 text-center text-sm text-white"
      >
        {linear
          ? 'Click the map in the middle of the area the linear move irrigates, or enter its coordinates below'
          : 'Click the map at the center of the pivot, or enter its coordinates below'}
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
    {#if locateError}<span class="text-status-irrigate-ink">{locateError}</span>{/if}
    {#if center}<span class="text-ink-muted"
        >{linear
          ? 'Drag the pin to move the linear move, the square corner handles to resize it, or the round handle to turn it.'
          : arc
            ? 'Drag the pin to move the pivot, the blue handle to set its radius, or the white handles to set the ends of its arc.'
            : 'Drag the pin to move the pivot, or the round handle to set its radius.'}</span
      >{/if}
  </div>
  {#if soils}
    <div class="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs" aria-live="polite">
      <span class="font-medium">Soil types:</span>
      {#if soilStatus === 'loading'}
        <span class="text-ink-muted">loading from the soil survey…</span>
      {:else if soilStatus === 'error'}
        <span class="text-ink-muted">the soil survey can't be reached right now.</span>
      {:else if soilStatus === 'zoom'}
        <span class="text-ink-muted">place the pivot, or zoom in, to see them.</span>
      {:else}
        {#each soilTypes.filter((type) => soilKeys.includes(type.key)) as type (type.key)}
          <span class="flex items-center gap-1"
            ><span class="size-3 rounded-sm border border-line" style:background={SOIL_COLORS[type.key]}
            ></span>{type.name}</span
          >
        {:else}
          <span class="text-ink-muted">no soil types matched here.</span>
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
