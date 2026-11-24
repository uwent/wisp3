<script module lang="ts">
  import { SYSTEM_SOURCES } from './systemLayers'
  import { ZONE_SOURCES } from './zones'

  /** Our sources (weather zones, irrigation groups, fields, systems, and overlays named overlay-*), carried over when the basemap changes */
  export const isOwnSource = (id: string) =>
    [...SYSTEM_SOURCES, ...ZONE_SOURCES].includes(id) || id.startsWith('overlay-')
</script>

<script lang="ts">
  import 'maplibre-gl/dist/maplibre-gl.css'

  import { mount, onMount, type Snippet, unmount, untrack } from 'svelte'
  import type { ExpressionSpecification, GeoJSONSource, Map as MapLibreMap, MapMouseEvent, Marker } from 'maplibre-gl'

  import { readPalette } from '@/lib/charts/palette'
  import type { LngLat } from '@/lib/geo'
  import type { FieldCard } from '@/lib/overview'
  import { onThemeChange } from '@/lib/theme'
  import { units as unitsFor, type UnitSystem } from '@/lib/units'
  import { weatherLines } from '@/lib/weatherSummary'
  import type { MapZone } from '@/types/serializers'

  import { type Basemap, BasemapSwitch, LABEL_FONT, labelPaint } from './basemaps'
  import { createMap, DEFAULT_VIEW } from './createMap'
  import BasemapToggle from './BasemapToggle.svelte'
  import MapLayersButton from './MapLayersButton.svelte'
  import { followRoads } from './roads.svelte'
  import { ButtonControl, FIT_ICON } from './controls'
  import SystemMarker from './SystemMarker.svelte'
  import FieldMarker from './FieldMarker.svelte'
  import HoverLabel from './HoverLabel.svelte'
  import { MapHover } from './hover.svelte'
  import {
    type FeatureCollection,
    type FieldBadges,
    fieldBadges,
    fieldFeatures,
    unoutlinedFields,
    type MapSystem,
    systemBounds,
    systemFeatures,
  } from './systems'
  import PlaceSearch from './PlaceSearch.svelte'
  import {
    addGlyphImages,
    addSystemLayers,
    FIELD_IDS,
    GROUP_IDS,
    FAR_ZOOM,
    hoverLines,
    SYSTEM_IDS,
    setFieldColors,
    setSystemColors,
    SYSTEM_LAYERS,
    systemHit,
  } from './systemLayers'
  import { loadMapLibre, showLayers } from './maplibre'
  import { addZoneLayers, setZones, showZones as showZoneLayers, zoneAt } from './zones'

  // The operation's irrigation systems on a map: each drawn in the system
  // color, a pivot or linear to scale and a point kind as its glyph (systemLayers.ts), with a marker
  // of its fields' badges at the center, and each irrigation group lightly outlined around its
  // systems. Fields with an outline are filled in their status, and its marker shows only the
  // fields without one; each outlined field has a badge per planting at its center (FieldMarker) and
  // its name along its top. Clicking a system selects it, and clicking a field or its badges selects
  // its system with that field, and clicking inside a group's outline elsewhere selects the group
  // (onselectgroup); the page shows its details in the panel (children) and adds its own
  // layers to the Layers panel (layers). Beside the pointer, the hover label names what's under it, down the stack
  // (group, system, field, then a marker's badge). Under them, the weather zones of the operation's
  // systems are outlined (zones): with nothing else under the pointer, the label has the zone's
  // weather, and a click there selects the zone (onselectzone).
  let {
    systems,
    groups,
    today,
    selectedId,
    selectedFieldId = null,
    highlighted,
    highlightedFields = null,
    showSystems = true,
    zones = [],
    showZones = true,
    selectedZoneId = null,
    onselectzone,
    onselectgroup,
    basemap,
    view,
    unitSystem = 'imperial',
    onselect,
    onbasemap,
    onviewchange,
    onload,
    layers,
    layersCount = 0,
    besideLayers,
    children,
  }: {
    systems: MapSystem[]
    /** The irrigation groups' outlines (groupFeatures), the selected one drawn more strongly */
    groups: FeatureCollection<{ name: string; selected: boolean }>
    /** For the plantings' days in the hover label */
    today: string
    selectedId: number | null
    /** The field selected with its system, highlighted on the map */
    selectedFieldId?: number | null
    /** The systems the list's filters keep (others are muted), or null when nothing's filtered */
    highlighted: Set<number> | null
    /** Likewise the fields */
    highlightedFields?: Set<number> | null
    /** Draw the systems' shapes and dots (the Irrigation systems layer) */
    showSystems?: boolean
    /** The weather zones of the operation's systems */
    zones?: MapZone[]
    /** Draw them, and say their weather on hover (the Weather zones layer) */
    showZones?: boolean
    /** The zone selected (its panel open), outlined more strongly */
    selectedZoneId?: number | null
    onselectzone?: (zoneId: number) => void
    onselectgroup?: (groupId: number) => void
    basemap: Basemap
    /** Where to start; without one the map fits every system */
    view: { center: LngLat; zoom: number } | null
    unitSystem?: UnitSystem
    onselect: (systemId: number | null, fieldId?: number | null) => void
    onbasemap: (basemap: Basemap) => void
    onviewchange: (view: { center: LngLat; zoom: number }) => void
    /** Once the map and our layers are on it, and again after a basemap change */
    onload?: (map: MapLibreMap) => void
    /** The page's own layers, in the Layers panel after the base map, and how many are on */
    layers?: Snippet
    layersCount?: number
    /** Beside the Layers button (the Map tab's overlay shown, to switch it off) */
    besideLayers?: Snippet
    children?: Snippet
  } = $props()

  // Below FAR_ZOOM a system is a few pixels across: its marker is one dot. Below NAME_ZOOM the
  // marker shows badges without the system's name.
  const NAME_ZOOM = 13
  const SYSTEM_ZOOM = 14

  let wrapper: HTMLDivElement
  let container: HTMLDivElement
  let map = $state<MapLibreMap>()
  followRoads(() => map)
  let zoom = $state(DEFAULT_VIEW.zoom)
  let placeSearch = $state<PlaceSearch>()

  type MarkerProps = {
    system: MapSystem
    fields: FieldCard[]
    today: string
    selected: boolean
    dimmed: boolean
    onselect: () => void
  }
  // eslint-disable-next-line svelte/prefer-svelte-reactivity -- bookkeeping for MapLibre's markers, not rendered from
  const markers = new Map<number, { marker: Marker; props: MarkerProps; component: ReturnType<typeof mount> }>()
  type FieldProps = {
    field: FieldBadges
    selected: boolean
    dimmed: boolean
    onselect: () => void
  }
  // eslint-disable-next-line svelte/prefer-svelte-reactivity -- as markers, by field
  const fieldMarkers = new Map<number, { marker: Marker; props: FieldProps; component: ReturnType<typeof mount> }>()

  // The hover label follows the pointer (MapHover): the map's features under it (hoverLines) and
  // every marker badge there (data-hover), the ones covered by another too (zoomed out, markers
  // overlap where their systems don't), or with nothing else there the weather zone's weather. The
  // cursor is a pointer where a click selects something.
  const hover = new MapHover(
    (m, point, event) => {
      const badges = document
        .elementsFromPoint(event.clientX, event.clientY)
        .filter((element): element is HTMLElement => element instanceof HTMLElement && !!element.dataset.hover)
        .flatMap((element) => element.dataset.hover!.split('\n'))
      let lines = [...new Set([...hoverLines(m, point), ...badges])]
      const zone = lines.length ? null : zoneUnder(m, point)
      if (zone) {
        const weather = weatherLines(zone.weather, unitsFor(unitSystem))
        lines = weather.length ? weather : ['No weather for this zone yet']
      }
      const selectable =
        !!zone ||
        badges.length > 0 ||
        lines.some((line) => !line.startsWith('Group:')) ||
        (!!onselectgroup && lines.length > 0)
      m.getCanvas().style.cursor = selectable ? 'pointer' : ''
      return lines
    },
    () => wrapper,
  )

  /** The shown weather zone at a point of the map, or null */
  const zoneUnder = (m: MapLibreMap, point: [number, number]) => {
    if (!showZones) return null
    const { lng, lat } = m.unproject(point)
    return zoneAt(zones, [lng, lat])
  }
  const selectedZone = () => zones.find((zone) => zone.id === selectedZoneId) ?? null

  const features = () => systemFeatures(systems, selectedId, highlighted)
  const fields = () => fieldFeatures(systems, selectedFieldId, highlighted, highlightedFields)

  function addOurLayers(m: MapLibreMap) {
    // Weather zones, under everything else of ours (the public overlays go under them)
    addZoneLayers(m, zones, selectedZone(), showZones)

    // Irrigation groups: a light shade inside a dashed line in the system color, named along it; the
    // selected group's shade and line stronger, as a selected field's are
    const palette = readPalette()
    m.addSource(GROUP_IDS.source, { type: 'geojson', data: groups })
    m.addLayer({
      id: GROUP_IDS.fill,
      type: 'fill',
      source: GROUP_IDS.source,
      paint: { 'fill-color': '#ffffff', 'fill-opacity': ['case', ['get', 'selected'], 0.18, 0.08] },
    })
    m.addLayer({
      id: GROUP_IDS.casing,
      type: 'line',
      source: GROUP_IDS.source,
      paint: {
        'line-color': palette.systemCasing,
        'line-width': ['case', ['get', 'selected'], 5, 4],
        'line-opacity': ['case', ['get', 'selected'], 0.8, 0.55],
      },
    })
    m.addLayer({
      id: GROUP_IDS.line,
      type: 'line',
      source: GROUP_IDS.source,
      paint: {
        'line-color': palette.system,
        'line-width': ['case', ['get', 'selected'], 3, 2],
        'line-dasharray': [3, 2],
      },
    })
    m.addLayer({
      id: GROUP_IDS.label,
      type: 'symbol',
      source: GROUP_IDS.source,
      layout: {
        'symbol-placement': 'line',
        'text-field': ['get', 'name'],
        'text-size': 12,
        'text-font': LABEL_FONT,
        'text-offset': [0, -0.8],
      },
      paint: { 'text-color': palette.system, 'text-halo-color': palette.systemCasing, 'text-halo-width': 1.5 },
    })

    // Fields with an outline, under the systems: a white line with a thin black edge around a
    // faint white fill (their plantings' badges carry the status)
    m.addSource(FIELD_IDS.source, { type: 'geojson', data: fields() as never })
    const OUTLINES: ExpressionSpecification = ['==', ['get', 'kind'], 'outline']
    m.addLayer({
      id: FIELD_IDS.fill,
      type: 'fill',
      source: FIELD_IDS.source,
      filter: OUTLINES,
      paint: {
        'fill-color': palette.field,
        'fill-opacity': ['case', ['get', 'dimmed'], 0.03, ['get', 'selected'], 0.25, 0.1],
      },
    })
    m.addLayer({
      id: FIELD_IDS.casing,
      type: 'line',
      source: FIELD_IDS.source,
      filter: OUTLINES,
      paint: {
        'line-color': palette.fieldCasing,
        'line-width': ['case', ['get', 'selected'], 5, 3],
        'line-opacity': ['case', ['get', 'dimmed'], 0.25, 0.8],
      },
    })
    m.addLayer({
      id: FIELD_IDS.line,
      type: 'line',
      source: FIELD_IDS.source,
      filter: OUTLINES,
      paint: {
        'line-color': palette.field,
        'line-width': ['case', ['get', 'selected'], 3, 1.5],
        'line-opacity': ['case', ['get', 'dimmed'], 0.35, 1],
      },
    })
    m.addLayer({
      id: FIELD_IDS.label,
      type: 'symbol',
      source: FIELD_IDS.source,
      filter: ['==', ['get', 'kind'], 'label'],
      minzoom: NAME_ZOOM,
      // Just above the top edge, clear of the badges at the center however small the field is
      layout: {
        'text-field': ['get', 'name'],
        'text-size': 12,
        'text-font': LABEL_FONT,
        'text-anchor': 'bottom',
        'text-offset': [0, -0.2],
      },
      paint: labelPaint(1.2),
    })

    addSystemLayers(m, features() as never, palette)
    showLayers(m, SYSTEM_LAYERS, showSystems)
  }

  async function syncMarkers() {
    const m = map
    if (!m) return
    const { Marker } = await loadMapLibre()
    // The page went (or the map was replaced) meanwhile
    if (map !== m) return
    // A system's marker shows its fields without an outline; zoomed out, it's one dot for all of them
    const ids = new Set(systems.map((system) => system.id))
    for (const [id, entry] of markers) {
      if (ids.has(id)) continue
      entry.marker.remove()
      unmount(entry.component)
      markers.delete(id)
    }
    for (const system of systems) {
      const state = {
        system,
        fields: unoutlinedFields(system),
        selected: system.id === selectedId,
        dimmed: highlighted !== null && !highlighted.has(system.id),
      }
      const entry = markers.get(system.id)
      if (entry) {
        Object.assign(entry.props, state)
        continue
      }
      const element = document.createElement('div')
      const props: MarkerProps = $state({ ...state, today, onselect: () => onselect(system.id) })
      const component = mount(SystemMarker, { target: element, props })
      const marker = new Marker({ element, anchor: 'center' }).setLngLat([system.longitude, system.latitude]).addTo(m)
      markers.set(system.id, { marker, props, component })
    }

    // An outlined field's plantings, as badges at its center
    const outlined = fieldBadges(systems, today)
    const fieldIds = new Set(outlined.map((field) => field.field_id))
    for (const [id, entry] of fieldMarkers) {
      if (fieldIds.has(id)) continue
      entry.marker.remove()
      unmount(entry.component)
      fieldMarkers.delete(id)
    }
    for (const field of outlined) {
      const state = {
        field,
        selected: field.field_id === selectedFieldId,
        dimmed:
          (highlighted !== null && !highlighted.has(field.system_id)) ||
          (highlightedFields !== null && !highlightedFields.has(field.field_id)),
      }
      const entry = fieldMarkers.get(field.field_id)
      if (entry) {
        Object.assign(entry.props, state)
        entry.marker.setLngLat(field.center)
        continue
      }
      const element = document.createElement('div')
      const props: FieldProps = $state({
        ...state,
        onselect: () => onselect(field.system_id, field.field_id),
      })
      const component = mount(FieldMarker, { target: element, props })
      const marker = new Marker({ element, anchor: 'center' }).setLngLat(field.center).addTo(m)
      fieldMarkers.set(field.field_id, { marker, props, component })
    }
  }

  // Redraw when the systems (farm filter), the selection or the window change
  $effect(() => {
    void [systems, selectedId, selectedFieldId, highlighted, highlightedFields]
    map?.getSource<GeoJSONSource>(SYSTEM_IDS.source)?.setData(features())
    map?.getSource<GeoJSONSource>(FIELD_IDS.source)?.setData(fields() as never)
    syncMarkers()
  })
  $effect(() => showLayers(map, SYSTEM_LAYERS, showSystems))
  // Read before the map is ready, so the effect depends on the groups (a short-circuited ?.
  // wouldn't read them, and the effect wouldn't rerun when they change)
  $effect(() => {
    const data = groups
    map?.getSource<GeoJSONSource>(GROUP_IDS.source)?.setData(data)
  })
  $effect(() => setZones(map, zones, selectedZone()))
  $effect(() => showZoneLayers(map, showZones))

  /** Fits the map to these systems (all of them by default) */
  export function fit(some: MapSystem[] = systems, animate = true) {
    const bounds = systemBounds(some)
    if (bounds) map?.fitBounds(bounds, { padding: 60, maxZoom: SYSTEM_ZOOM, duration: animate ? 800 : 0 })
  }

  /** Brings a system into view beside the panel that opens for it */
  export function show(systemId: number) {
    const system = systems.find((p) => p.id === systemId)
    if (!map || !system) return
    const wide = wrapper.clientWidth >= 640
    map.flyTo({
      center: [system.longitude, system.latitude],
      zoom: Math.max(map.getZoom(), NAME_ZOOM + 0.5),
      offset: wide ? [-170, 0] : [0, -wrapper.clientHeight * 0.2],
    })
  }

  export const getMap = () => map

  const basemapSwitch = new BasemapSwitch(
    untrack(() => basemap),
    {
      map: () => map,
      isOwn: isOwnSource,
      show: (to) => onbasemap(to),
      after: () => {
        if (!map) return
        // The new style has none of our icons
        addGlyphImages(map)
        // The style's system layers have the palette of the old theme only if it changed meanwhile
        map.getSource<GeoJSONSource>(SYSTEM_IDS.source)?.setData(features())
        map.getSource<GeoJSONSource>(FIELD_IDS.source)?.setData(fields() as never)
        onload?.(map)
      },
    },
  )

  function onClick(event: MapMouseEvent) {
    placeSearch?.close()
    if (!map) return
    // A pin or a field selects its system with that field; else a system, a group, a zone, or nothing
    let hit = systemHit(map, event.point)
    if (hit?.kind === 'group' && !onselectgroup) hit = null
    if (!hit) {
      const zone = onselectzone && zoneUnder(map, [event.point.x, event.point.y])
      return zone ? onselectzone!(zone.id) : onselect(null)
    }
    if (hit.kind === 'group') onselectgroup!(hit.groupId)
    else if (hit.kind === 'system') onselect(hit.systemId)
    else onselect(hit.systemId, hit.fieldId)
  }

  onMount(() => {
    const cleanups: (() => void)[] = []

    const remove = createMap(
      container,
      basemap,
      (m, maplibre) => {
        map = m
        m.addControl(new ButtonControl('Fit all irrigation systems', FIT_ICON, () => fit()), 'top-right')
        m.addControl(
          new maplibre.GeolocateControl({ positionOptions: { enableHighAccuracy: true }, trackUserLocation: false }),
          'top-right',
        )
        m.addControl(
          new maplibre.ScaleControl({ unit: unitSystem === 'metric' ? 'metric' : 'imperial' }),
          'bottom-left',
        )
        if (!view) fit(systems, false)

        m.on('load', () => {
          addOurLayers(m)
          syncMarkers()
          onload?.(m)
        })
        m.on('click', onClick)
        // A style image dropped with the old style (a basemap change) comes back
        m.on('styleimagemissing', () => addGlyphImages(m))
        cleanups.push(hover.attach(m))
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
            const palette = readPalette()
            setSystemColors(m, palette)
            setFieldColors(m, palette)
          }),
        )
      },
      view ?? {},
    )

    return () => {
      cleanups.forEach((cleanup) => cleanup())
      for (const { component } of [...markers.values(), ...fieldMarkers.values()]) unmount(component)
      markers.clear()
      fieldMarkers.clear()
      remove()
      map = undefined
    }
  })
</script>

<div
  bind:this={wrapper}
  class="group/map relative size-full overflow-hidden bg-surface"
  data-far={zoom < FAR_ZOOM ? '' : undefined}
  data-mid={zoom >= FAR_ZOOM && zoom < NAME_ZOOM ? '' : undefined}
>
  <div
    bind:this={container}
    class="size-full"
    role="application"
    aria-label="Map of the operation's systems. Select a system to see its fields."
  ></div>

  <div class="pointer-events-none absolute top-2 left-2 flex w-[calc(100%-4rem)] flex-col gap-2">
    <div class="flex flex-wrap items-start gap-2 *:pointer-events-auto">
      <BasemapToggle value={basemap} onchange={(to) => basemapSwitch.change(to)} />
      <MapLayersButton id="map-layers" {basemap} count={layersCount}>
        {@render layers?.()}
      </MapLayersButton>
      {@render besideLayers?.()}
    </div>
    <div class="pointer-events-auto hidden w-full max-w-68 sm:block">
      <PlaceSearch bind:this={placeSearch} {map} maxZoom={SYSTEM_ZOOM - 1} />
    </div>
  </div>

  <HoverLabel label={hover.label} />

  {@render children?.()}
</div>
