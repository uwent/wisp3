<script lang="ts">
  import 'maplibre-gl/dist/maplibre-gl.css'

  import { onMount, untrack } from 'svelte'
  import { Link } from '@inertiajs/svelte'
  import type { GeoJSONSource, Map as MapLibreMap, Marker as MarkerClass } from 'maplibre-gl'

  import Button from '@/lib/components/Button.svelte'
  import {
    bearing,
    DEFAULT_RADIUS_FT,
    destination,
    distanceM,
    draftShape,
    edgePointer,
    FEET_PER_METER,
    isPoint,
    KIND_NOUNS,
    MAX_RADIUS_FT,
    MIN_SIZE_FT,
    shapeOutline,
    linearCorners,
    linearOf,
    offset,
    POINT_SURVEY_RADIUS_FT,
    resizeLinear,
    snapBearing,
    sweep,
    travelArrow,
    type LngLat,
    type SystemShape,
    type ShapeDraft,
  } from '@/lib/geo'
  import { BasemapSwitch, LABEL_FONT, labelPaint, type Basemap } from '@/lib/map/basemaps'
  import { createMap } from '@/lib/map/createMap'
  import BasemapToggle from '@/lib/map/BasemapToggle.svelte'
  import { resizeCursor, ROTATE_CURSOR } from '@/lib/map/cursors'
  import PlaceSearch from '@/lib/map/PlaceSearch.svelte'
  import { readPalette } from '@/lib/charts/palette'
  import { boundaryBounds, boundaryCenter } from '@/lib/boundary'
  import { boundsOf } from '@/lib/geo'
  import type { FileShapes } from '@/lib/outlines/fileShapes'
  import {
    addSavedFieldLayers,
    addShapeTier,
    SAVED_FIELD_SOURCE,
    savedFieldData,
    shapeTierLayers,
    type Swatch,
    type SavedField,
    swatches,
  } from '@/lib/outlines/layers'
  import { addReferenceLayers, SYSTEM_HOVER_LAYERS } from '@/lib/outlines/references'
  import HoverLabel from '@/lib/map/HoverLabel.svelte'
  import { MapHover, propertiesAt } from '@/lib/map/hover.svelte'
  import { showLayers } from '@/lib/map/maplibre'
  import MapLegend from '@/lib/map/MapLegend.svelte'
  import { newOutlineImport } from '@/routes'
  import { SOIL_SOURCE, SoilTypesLayer } from '@/lib/map/soilTypes.svelte'
  import SoilTypesHover from '@/lib/map/SoilTypesHover.svelte'
  import SoilTypesLegend from '@/lib/map/SoilTypesLegend.svelte'
  import MapLayersButton from '@/lib/map/MapLayersButton.svelte'
  import { followRoads } from '@/lib/map/roads.svelte'
  import SoilTypesOption from '@/lib/map/SoilTypesOption.svelte'
  import type { Bounds } from '@/lib/soils'

  type Outline = SystemShape & { id: number; name: string }

  // The system location picker: click the map to place the system's center, drag the
  // center or the handles to adjust it. A center pivot has a handle on its edge for the radius and,
  // for a partial circle, one at each end of the arc; a linear has handles on two opposite
  // corners (its front left and back right, facing its direction of travel) and one past its front
  // end that turns it. A point kind (a traveler, drip, a location) is just the pin. The group's
  // other irrigation systems are drawn for reference. A place search moves
  // the map (it doesn't place the system), and an arrow at the edge points back to the system when
  // it's out of view. The map shares the setup maps' symbology (lib/outlines/layers.ts), with a
  // legend: bottom to top, a kept outline file's shapes not yet imported (fileShapes, a layer on to
  // start with, gray and named, a guide to place systems on), the operation's saved fields, its other
  // systems (muted) and this one. A saved system's map starts locked (`locked`), so a stray click or drag
  // can't move it: Edit on the map unlocks it, Done editing keeps the changes (the form's Save saves
  // them) and Cancel puts back the shape from before, as on the field shape page.
  let {
    shape = $bindable(),
    others = [],
    frame = null,
    soilTypes = [],
    height = 'min(36rem, 60vh)',
    locked = false,
    fileShapes = null,
    fields = [],
  }: {
    shape: ShapeDraft
    others?: Outline[]
    /** [[west, south], [east, north]]: what the map opens on while the system has no location (its farm's systems and fields), else all of others */
    frame?: [LngLat, LngLat] | null
    /** Names for the soil types layer */
    soilTypes?: { key: string; name: string }[]
    height?: string
    /** Start locked (an existing system): the map moves nothing until Edit on the map */
    locked?: boolean
    /** A kept outline file's shapes not yet imported (lib/outlines/fileShapes.ts) */
    fileShapes?: FileShapes | null
    /** The operation's field outlines */
    fields?: SavedField[]
  } = $props()

  // Wisconsin's Central Sands, where most WISP systems are
  const SYSTEM_ZOOM = 14
  // The least an arc can sweep with its handles
  const MIN_SWEEP_DEG = 5

  // Our sources, carried over when the basemap changes
  const OWN_SOURCES = ['file-shapes', SAVED_FIELD_SOURCE, 'reference', 'system', SOIL_SOURCE]
  const FILE_SHAPE_LAYERS = [...shapeTierLayers('file-shapes', 'skip'), 'file-shapes-label']
  // This system, in a stronger blue than the others' cyan
  const THIS_SYSTEM = '#3987e5'
  let fileShapesOn = $state(true)
  // Soil types are shown around the system, or in the view once zoomed in this far without one
  const SOIL_ZOOM = 13
  const SOIL_MARGIN_M = 900

  // Where to click, above the map while the system has no location, and over it until the map's touched
  const PLACE_HINT = 'Click the map at the center of the irrigation system, or enter its coordinates below.'
  let touched = $state(false)
  // A click nearer the center than this share of the system's reach doesn't move it (a click meant for the pin)
  const MOVE_SHARE = 0.15

  type Handle = 'radius' | 'start' | 'end' | 'frontLeft' | 'backRight' | 'rotate'

  let container: HTMLDivElement
  let map: MapLibreMap | undefined = $state()
  followRoads(() => map)
  let Marker: typeof MarkerClass | undefined
  let centerMarker: MarkerClass | undefined
  let handles: Partial<Record<Handle, MarkerClass>> = {}
  let handleSet = ''
  let basemap = $state<Basemap>('imagery')
  const soilLayer = new SoilTypesLayer(() => soilTypes, soilArea, FILE_SHAPE_LAYERS[0])
  /** For the soil survey beside the map, to show its soils on the map */
  export const soil = soilLayer
  let pointer = $state<{ x: number; y: number; angle: number } | null>(null)
  let placeSearch: PlaceSearch | undefined = $state()
  // Whether clicks and drags change the shape; the shape when editing began, for Cancel
  let editing = $state(untrack(() => !locked))
  let before = $state.raw<ShapeDraft | null>(null)

  function startEditing() {
    before = { ...shape }
    editing = true
  }
  function doneEditing() {
    before = null
    editing = false
  }
  // Puts back the location and size from before (the kind is the form's, not the map's)
  function cancelEditing() {
    if (before) Object.assign(shape, { ...before, kind: shape.kind })
    doneEditing()
  }

  // A new frame (another farm chosen) moves the map there, until the system has a location
  let framed = ''
  $effect(() => {
    const key = JSON.stringify(frame)
    if (!map || !frame || center || key === framed) return
    framed = key
    map.fitBounds(frame, { padding: 60, maxZoom: SYSTEM_ZOOM, duration: 600 })
  })

  const linear = $derived(shape.kind === 'linear')
  const point = $derived(isPoint(shape.kind))
  // "system", "drip block"
  const noun = $derived(KIND_NOUNS[shape.kind])
  const outline = $derived(draftShape(shape))
  const center = $derived<LngLat | null>(outline && [outline.longitude, outline.latitude])
  const radiusM = $derived((shape.radiusFt ?? DEFAULT_RADIUS_FT) / FEET_PER_METER)
  const machine = $derived(
    linearOf({ length_ft: shape.lengthFt, travel_ft: shape.travelFt, travel_bearing_deg: shape.travelBearing }),
  )
  // How far the system reaches from its center
  const reachM = $derived(
    point
      ? POINT_SURVEY_RADIUS_FT / FEET_PER_METER
      : linear
        ? Math.hypot(machine.lengthFt, machine.travelFt) / 2 / FEET_PER_METER
        : radiusM,
  )
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

  // The file's shapes, as the import map draws a skipped one, and named
  const fileShapeData = () => ({
    type: 'FeatureCollection' as const,
    features: (fileShapes?.shapes ?? []).flatMap((fileShape) => [
      {
        type: 'Feature' as const,
        properties: { name: '', hoverName: fileShape.name, state: 'skip' },
        geometry: fileShape.boundary,
      },
      {
        type: 'Feature' as const,
        properties: { name: fileShape.name },
        geometry: { type: 'Point' as const, coordinates: boundaryCenter(fileShape.boundary) },
      },
    ]),
  })

  function addLayers(m: MapLibreMap) {
    const palette = readPalette()
    m.addSource('file-shapes', { type: 'geojson', data: fileShapeData() as never })
    addShapeTier(m, palette, 'file-shapes', 'skip', fileShapesOn)
    addSavedFieldLayers(m, palette, fields)
    m.addLayer({
      id: 'file-shapes-label',
      type: 'symbol',
      source: 'file-shapes',
      filter: ['==', ['geometry-type'], 'Point'],
      layout: {
        visibility: fileShapesOn ? 'visible' : 'none',
        'text-field': ['get', 'name'],
        'text-size': 12,
        'text-font': LABEL_FONT,
      },
      paint: labelPaint(),
    })
    addReferenceLayers(
      m,
      others.map((other) => ({ name: other.name, shape: other })),
      { ownFirst: false },
    )
    m.addSource('system', { type: 'geojson', data: { type: 'FeatureCollection', features: [] } })
    m.addLayer({
      id: 'system-fill',
      type: 'fill',
      source: 'system',
      paint: { 'fill-color': THIS_SYSTEM, 'fill-opacity': 0.25 },
    })
    m.addLayer({
      id: 'system-line',
      type: 'line',
      source: 'system',
      paint: { 'line-color': THIS_SYSTEM, 'line-width': ['match', ['get', 'role'], 'arrow', 2, 2.5] },
      layout: { 'line-cap': 'round', 'line-join': 'round' },
    })
    drawSystem()
  }

  function drawSystem() {
    const source = map?.getSource<GeoJSONSource>('system')
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
      features: outline && !point ? [feature(shapeOutline(outline)!), ...extras] : [],
    })
  }

  // Where each of the shape's handles goes
  function handlePositions(): Partial<Record<Handle, LngLat>> {
    if (!center || point) return {}
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
    radius: { className: 'rounded-full bg-map-handle', title: 'Drag to set the radius' },
    start: { className: 'rounded-full bg-white', title: 'Drag to set where the arc starts' },
    end: { className: 'rounded-full bg-white', title: 'Drag to set where the arc ends' },
    frontLeft: { className: 'rounded-sm bg-map-handle', title: 'Drag to resize the linear' },
    backRight: { className: 'rounded-sm bg-map-handle', title: 'Drag to resize the linear' },
    rotate: { className: 'rounded-full bg-white', title: 'Drag to turn the linear' },
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
    // Keep the map from panning, or placing the system on the click that ends a drag
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
    if (!editing) {
      // Locked: the pin shows where the system is, and nothing moves
      Object.values(handles).forEach((marker) => marker.remove())
      handles = {}
      handleSet = ''
    }
    if (!centerMarker) {
      centerMarker = new Marker({ draggable: editing, color: readPalette().handle }).setLngLat(center).addTo(map)
      centerMarker.on('drag', () => {
        const { lng, lat } = centerMarker!.getLngLat()
        setCenter([lng, lat])
      })
    } else {
      centerMarker.setLngLat(center)
      centerMarker.setDraggable(editing)
    }
    if (!editing) return
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
        element.classList.replace('border-white', 'border-map-handle')
      element.title = HANDLE_STYLE[name].title
      element.style.cursor = cursor
      followPointer(element, name)
      handles[name] = new Marker({ element }).setLngLat(position).addTo(map)
    }
    handleSet = set
  }

  // An arrow at the map's edge when the system is placed but scrolled out of view
  function updatePointer() {
    if (!map || !center) return (pointer = null)
    const point = map.project(center)
    pointer = edgePointer(point, container.clientWidth, container.clientHeight, 28)
  }

  // Redraw when the shape changes, whether from the map or the form's inputs
  $effect(() => {
    void [outline, handleBearing, rotatePosition, editing]
    drawSystem()
    placeMarkers()
    updatePointer()
  })

  // Soil types around the system: the survey's map units colored and labeled by
  // the WISP soil type their surface texture suggests, loaded for an area around the system (or the
  // view, zoomed in, before it's placed) and again when the system moves out of it
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

  // The file's shapes, once they're in: drawn, and framed with the farm's systems while the system has no location
  let framedFile: FileShapes | null = null
  $effect(() => {
    const file = fileShapes
    const m = map
    untrack(() => {
      m?.getSource<GeoJSONSource>('file-shapes')?.setData(fileShapeData() as never)
      if (!m || !file || file === framedFile || center) return
      framedFile = file
      const corners = file.shapes.flatMap((fileShape) => boundaryBounds(fileShape.boundary))
      m.fitBounds(boundsOf([...corners, ...(frame ?? [])])!, { padding: 60, maxZoom: SYSTEM_ZOOM, duration: 600 })
    })
  })
  $effect(() => {
    const on = fileShapesOn
    untrack(() => showLayers(map, FILE_SHAPE_LAYERS, on))
  })
  $effect(() => {
    const outlines = fields
    const m = map
    untrack(() => m?.getSource<GeoJSONSource>(SAVED_FIELD_SOURCE)?.setData(savedFieldData(outlines) as never))
  })

  // The legend: this system and the others, then the saved fields and the file's shapes when shown
  const legend = swatches(readPalette())
  const legendRows = $derived<Swatch[][]>([
    [
      { label: `This ${noun}`, color: THIS_SYSTEM, width: 2.5, filled: true, round: true },
      ...(others.length ? [{ ...legend.system, label: 'Other irrigation systems' }] : []),
    ],
    [
      ...(fields.length ? [legend.saved] : []),
      ...(fileShapes && fileShapesOn ? [{ ...legend.skip, label: 'Not yet imported' }] : []),
    ],
  ])

  // Load again when the system moves out of the loaded area
  $effect(() => {
    void [center, reachM]
    soilLayer.load()
  })

  const basemapSwitch = new BasemapSwitch(
    untrack(() => basemap),
    {
      map: () => map,
      isOwn: (id) => OWN_SOURCES.includes(id),
      show: (to) => (basemap = to),
      after: () => drawSystem(),
    },
  )

  function showSystem() {
    if (center) map?.flyTo({ center, zoom: Math.max(map.getZoom(), SYSTEM_ZOOM - 1) })
  }

  // Beside the pointer: this system, the others, the saved fields and the file's shapes under it,
  // and what a click there would do
  let box = $state<HTMLDivElement>()
  const hover = new MapHover(
    (m, at) => {
      const named = [
        ...new Set([
          ...propertiesAt(m, at, ['system-fill']).map(() => `This ${noun}`),
          ...propertiesAt(m, at, SYSTEM_HOVER_LAYERS).map((properties) => `System: ${properties.hoverName}`),
          ...propertiesAt(m, at, ['saved-fields-hit']).map((properties) => String(properties.hover)),
          ...propertiesAt(m, at, [FILE_SHAPE_LAYERS[0]]).map(
            (properties) => `Not yet imported: ${properties.hoverName || 'unnamed shape'}`,
          ),
        ]),
      ]
      // With something named, the soil type joins this label in place of its own (SoilTypesHover)
      const soil = propertiesAt(m, at, ['soil-types-fill']).map((properties) => `Soil: ${properties.name}`)
      return named.length ? [...named, ...soil.slice(0, 1)] : []
    },
    () => box,
    (m, at) => {
      if (!editing) return null
      if (!center) return `Click to place the ${noun} here`
      // A click this near the system's center doesn't move it
      const { lng, lat } = m.unproject(at)
      return distanceM(center, [lng, lat]) > reachM * MOVE_SHARE ? `Click to move the ${noun} here` : null
    },
  )
  let stopHover = () => {}

  onMount(() => {
    const remove = createMap(container, basemap, (m, maplibre) => {
      const { LngLatBounds } = maplibre
      Marker = maplibre.Marker
      // Under the zoom buttons: the map to where the grower is (it moves the map, not the system)
      m.addControl(
        new maplibre.GeolocateControl({ positionOptions: { enableHighAccuracy: true }, trackUserLocation: false }),
        'top-right',
      )
      if (center) {
        m.jumpTo({ center, zoom: SYSTEM_ZOOM })
      } else if (frame) {
        m.fitBounds(frame, { padding: 60, maxZoom: SYSTEM_ZOOM, duration: 0 })
        framed = JSON.stringify(frame)
      } else if (others.length) {
        const bounds = new LngLatBounds()
        others.forEach((other) => bounds.extend([other.longitude, other.latitude]))
        m.fitBounds(bounds, { padding: 80, maxZoom: SYSTEM_ZOOM - 1, duration: 0 })
      }
      m.on('load', () => {
        addLayers(m)
        placeMarkers()
        stopHover = hover.attach(m)
      })
      soilLayer.attach(m)
      m.on('move', updatePointer)
      m.on('resize', updatePointer)
      m.on('rotate', placeMarkers)
      m.on('click', (event) => {
        placeSearch?.close()
        if (!editing) return
        // A click away from the system moves it; clicks on the markers are drags. Placing it zooms in
        // to fit it, handles and all, so they're apart and in view.
        const point: LngLat = [event.lngLat.lng, event.lngLat.lat]
        if (!center) {
          setCenter(point)
          const bounds = new LngLatBounds()
          const ring = shapeOutline(draftShape(shape)!) ?? [point]
          for (const corner of [...ring, ...Object.values(handlePositions())]) {
            bounds.extend(corner)
          }
          if (m.getZoom() < SYSTEM_ZOOM - 1) m.fitBounds(bounds, { padding: 40, maxZoom: SYSTEM_ZOOM, duration: 600 })
        } else if (distanceM(center, point) > reachM * MOVE_SHARE) {
          setCenter(point)
        }
      })
      map = m
    })
    return () => {
      stopHover()
      remove()
    }
  })
</script>

<div class="space-y-2">
  {#if !center}<p class="text-sm text-ink-muted">{PLACE_HINT}</p>{/if}
  {#if fileShapes}
    <p class="text-sm text-ink-muted">
      {`The ${fileShapes.shapes.length === 1 ? 'shape' : `${fileShapes.shapes.length.toLocaleString('en-US')} shapes`} from ${fileShapes.fileName} not yet imported ${fileShapes.shapes.length === 1 ? 'is' : 'are'} a layer on the map (Layers), gray and named, to place your irrigation systems on. Once their systems are set up, `}<Link
        href={newOutlineImport()}
        class="text-brand-600 underline">import the shapes as fields</Link
      >.
    </p>
  {/if}
  <!-- Any use of the map takes the hint off it -->
  <div
    bind:this={box}
    class="relative overflow-hidden rounded-lg border border-line"
    style:height
    onpointerdown={() => (touched = true)}
    onwheel={() => (touched = true)}
    onkeydown={() => (touched = true)}
    role="presentation"
  >
    <div
      bind:this={container}
      class="size-full"
      aria-label={editing
        ? `Map: click to place the ${noun}, or enter its coordinates${point ? '' : ' and size'} in the fields below`
        : `Map of the ${noun}: Edit on the map to move${point ? '' : ' or resize'} it`}
      role="application"
    ></div>

    <!-- Top left, in a column: the map's toggles, the place search while editing, and a saved
         system's lock (the attribution and the legend take the bottom corners) -->
    <div
      class="pointer-events-none absolute top-2 left-2 flex w-[min(18rem,calc(100%-4rem))] flex-col items-start gap-2"
    >
      <div class="pointer-events-auto flex gap-2">
        <BasemapToggle value={basemap} onchange={(to) => basemapSwitch.change(to)} />
        <MapLayersButton
          id="system-map-layers"
          {basemap}
          count={(soilLayer.on ? 1 : 0) + (fileShapes && fileShapesOn ? 1 : 0)}
        >
          {#if fileShapes}
            <label class="flex items-start gap-2">
              <input type="checkbox" class="mt-1" bind:checked={fileShapesOn} />
              <span>
                {`Shapes from ${fileShapes.fileName}`}
                <span class="block text-xs text-ink-muted"
                  >Your field shapes not yet imported, to place your irrigation systems on</span
                >
              </span>
            </label>
          {/if}
          <SoilTypesOption layer={soilLayer} />
        </MapLayersButton>
      </div>
      {#if editing}
        <div class="pointer-events-auto w-full">
          <PlaceSearch bind:this={placeSearch} {map} maxZoom={SYSTEM_ZOOM - 1} />
        </div>
      {/if}
      <!-- A saved system's lock: Edit on the map, then keep or undo what the map changed, as on the
           field shape page -->
      {#if editing && before}
        <div
          class="pointer-events-auto flex flex-wrap items-center gap-2 rounded-lg border border-line bg-surface-raised p-2 shadow-lg"
          role="group"
          aria-label="The {noun} on the map"
        >
          <Button type="button" onclick={doneEditing}>Done editing</Button>
          <Button type="button" variant="secondary" onclick={cancelEditing}>Cancel</Button>
        </div>
      {:else if !editing}
        <Button type="button" variant="secondary" class="pointer-events-auto shadow-lg" onclick={startEditing}
          >Edit on the map</Button
        >
      {/if}
    </div>

    {#if !center && !touched}
      <p
        aria-hidden="true"
        class="pointer-events-none absolute top-1/3 left-1/2 w-[min(20rem,calc(100%-2rem))] -translate-x-1/2 rounded-md bg-black/60 px-3 py-2 text-center text-sm text-white"
      >
        {PLACE_HINT}
      </p>
    {/if}

    {#if pointer}
      <button
        type="button"
        class="absolute flex size-9 -translate-1/2 items-center justify-center rounded-full border-2 border-white bg-map-handle text-white shadow-lg hover:scale-110"
        style:left="{pointer.x}px"
        style:top="{pointer.y}px"
        aria-label="The {noun} is off the map: show it"
        title="Show the {noun}"
        onclick={showSystem}
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

    {#if !hover.label}<SoilTypesHover layer={soilLayer} />{/if}
    <HoverLabel label={hover.label} />

    <MapLegend rows={legendRows} />
  </div>
  <div class="flex flex-wrap items-center gap-3 text-sm">
    {#if center && !editing}<span class="text-ink-muted"
        >Locked so a stray click can't move the {noun}: Edit on the map to move{point ? '' : ' or resize'} it.</span
      >
    {:else if center}<span class="text-ink-muted"
        >{point
          ? `Drag the pin to move the ${noun}.`
          : linear
            ? 'Drag the pin to move the linear, the square corner handles to resize it, or the round handle to turn it.'
            : arc
              ? 'Drag the pin to move the pivot, the blue handle to set its radius, or the white handles to set the ends of its arc.'
              : 'Drag the pin to move the pivot, or the round handle to set its radius.'}</span
      >{/if}
  </div>
  <SoilTypesLegend layer={soilLayer} {soilTypes} zoomHint="place the {noun}, or zoom in, to see them." />
</div>
