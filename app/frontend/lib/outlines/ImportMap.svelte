<script lang="ts">
  import 'maplibre-gl/dist/maplibre-gl.css'

  import { onMount, untrack } from 'svelte'
  import type { ExpressionSpecification, GeoJSONSource, Map as MapLibreMap } from 'maplibre-gl'

  import { type Palette, readPalette } from '@/lib/charts/palette'
  import { boundsOf } from '@/lib/geo'
  import { type Boundary, boundaryBounds, boundaryCenter } from '@/lib/boundary'
  import { type Basemap, BasemapSwitch, LABEL_FONT, labelPaint } from '@/lib/map/basemaps'
  import { createMap } from '@/lib/map/createMap'
  import BasemapToggle from '@/lib/map/BasemapToggle.svelte'
  import MapLayersButton from '@/lib/map/MapLayersButton.svelte'
  import { followRoads } from '@/lib/map/roads.svelte'
  import { onThemeChange } from '@/lib/theme'

  import { addReferenceLayers, type Reference } from './references'

  export type ShapeOnMap = { boundary: Boundary; label: string; state: 'skip' | 'field' | 'new' }

  // The shapes from an outline file, named as in the list beside the map
  // and colored by where each goes (an existing field, a new one, or skipped), over the operation's
  // systems and outlined fields, with a legend of the colors below. Clicking a shape picks its row.
  let {
    shapes,
    references,
    selected = null,
    onselect,
    fileKey = 0,
    height = '28rem',
    fill = false,
  }: {
    shapes: ShapeOnMap[]
    /** Changes with each file read, to fit the map to its shapes */
    fileKey?: number
    references: Reference[]
    selected?: number | null
    onselect?: (index: number) => void
    height?: string
    /** Fills its box's height (at least 24rem) in place of a fixed height */
    fill?: boolean
  } = $props()

  // An existing field in a depth blue, a new one in the ok status green, a skipped shape muted; read
  // again when the theme changes
  const colorsFrom = (palette: Palette): Record<ShapeOnMap['state'], string> => ({
    field: palette.depths[1],
    new: palette.status.ok,
    skip: palette.inkMuted,
  })
  let colors = $state(colorsFrom(readPalette()))
  const LEGEND: { state: ShapeOnMap['state']; label: string }[] = [
    { state: 'skip', label: 'Skip' },
    { state: 'new', label: 'New field' },
    { state: 'field', label: 'Update field' },
  ]
  const colorExpression = (): ExpressionSpecification => [
    'match',
    ['get', 'state'],
    'field',
    colors.field,
    'new',
    colors.new,
    colors.skip,
  ]

  let container: HTMLDivElement
  let map = $state<MapLibreMap>()
  followRoads(() => map)
  let basemap = $state<Basemap>('imagery')

  const data = () => ({
    type: 'FeatureCollection' as const,
    features: shapes.flatMap((shape, index) => [
      {
        type: 'Feature' as const,
        id: index,
        properties: { index, state: shape.state, selected: index === selected, label: '' },
        geometry: shape.boundary,
      },
      {
        type: 'Feature' as const,
        properties: { index, state: shape.state, selected: index === selected, label: shape.label },
        geometry: { type: 'Point' as const, coordinates: boundaryCenter(shape.boundary) },
      },
    ]),
  })

  /** Fit the map to the shapes going somewhere, or every shape when none is (a county file's skipped thousands) */
  export function fit() {
    if (!map || !shapes.length) return
    const going = shapes.filter((shape) => shape.state !== 'skip')
    const bounds = boundsOf((going.length ? going : shapes).flatMap((shape) => boundaryBounds(shape.boundary)))!
    map.fitBounds(bounds, { padding: 48, maxZoom: 16, duration: 0 })
  }

  function addLayers(m: MapLibreMap) {
    addReferenceLayers(m, references)
    const color = colorExpression()
    m.addSource('shapes', { type: 'geojson', data: data() as never })
    m.addLayer({
      id: 'shapes-fill',
      type: 'fill',
      source: 'shapes',
      filter: ['!=', ['geometry-type'], 'Point'],
      paint: { 'fill-color': color, 'fill-opacity': ['case', ['get', 'selected'], 0.5, 0.3] },
    })
    m.addLayer({
      id: 'shapes-line',
      type: 'line',
      source: 'shapes',
      filter: ['!=', ['geometry-type'], 'Point'],
      paint: { 'line-color': color, 'line-width': ['case', ['get', 'selected'], 4, 2] },
    })
    m.addLayer({
      id: 'shapes-label',
      type: 'symbol',
      source: 'shapes',
      filter: ['==', ['geometry-type'], 'Point'],
      layout: { 'text-field': ['get', 'label'], 'text-size': 13, 'text-font': LABEL_FONT },
      paint: labelPaint(1.5),
    })
    m.on('click', 'shapes-fill', (event) => {
      const index = event.features?.[0]?.properties?.index
      if (typeof index === 'number') onselect?.(index)
    })
    m.on('mouseenter', 'shapes-fill', () => (m.getCanvas().style.cursor = 'pointer'))
    m.on('mouseleave', 'shapes-fill', () => (m.getCanvas().style.cursor = ''))
  }

  const basemapSwitch = new BasemapSwitch(
    untrack(() => basemap),
    {
      map: () => map,
      isOwn: (id) => id === 'reference' || id === 'shapes',
      show: (to) => (basemap = to),
    },
  )

  onMount(() => {
    const remove = createMap(container, basemap, (m) =>
      m.on('load', () => {
        map = m
        addLayers(m)
        fit()
      }),
    )
    const stopFollowing = onThemeChange(() => {
      colors = colorsFrom(readPalette())
      if (!map?.getLayer('shapes-fill')) return
      map.setPaintProperty('shapes-fill', 'fill-color', colorExpression())
      map.setPaintProperty('shapes-line', 'line-color', colorExpression())
    })
    return () => {
      stopFollowing()
      remove()
    }
  })

  // A changed choice or selection recolors the shapes; a new file (fileKey) also fits the map to them
  $effect(() => {
    void [shapes, selected]
    untrack(() => map?.getSource<GeoJSONSource>('shapes')?.setData(data() as never))
  })
  $effect(() => {
    void fileKey
    untrack(fit)
  })
  // A shape picked from its card, out of view, is brought into it
  $effect(() => {
    if (selected === null) return
    const shape = untrack(() => shapes[selected])
    if (!map || !shape) return
    const center = boundaryCenter(shape.boundary)
    if (!map.getBounds().contains(center)) map.easeTo({ center })
  })
</script>

<div class="flex flex-col gap-3 {fill ? 'h-full' : ''}">
  <div
    class="relative overflow-hidden rounded-lg border border-line {fill ? 'min-h-[24rem] flex-1' : ''}"
    style:height={fill ? undefined : height}
  >
    <div
      bind:this={container}
      class="h-full w-full"
      role="img"
      aria-label="Map of the file's shapes, named as in the list beside it"
    ></div>
    <div class="absolute top-2 left-2 flex gap-2">
      <BasemapToggle value={basemap} onchange={(to) => basemapSwitch.change(to)} />
      <MapLayersButton id="import-map-layers" {basemap} />
    </div>
  </div>
  <p class="flex flex-wrap gap-x-4 text-xs text-ink-muted">
    {#each LEGEND as { state, label } (state)}
      <span>
        <span class="inline-block size-3 rounded-sm align-middle" style:background-color={colors[state]}
        ></span>{` ${label}`}
      </span>
    {/each}
  </p>
</div>
