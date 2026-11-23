<script lang="ts">
  import 'maplibre-gl/dist/maplibre-gl.css'

  import { onMount, untrack } from 'svelte'
  import type { ExpressionSpecification, GeoJSONSource, Map as MapLibreMap } from 'maplibre-gl'

  import { readPalette } from '@/lib/charts/palette'
  import { boundsOf } from '@/lib/geo'
  import { type Boundary, boundaryBounds, boundaryCenter } from '@/lib/boundary'
  import { type Basemap, BasemapSwitch, LABEL_FONT, labelPaint } from '@/lib/map/basemaps'
  import { createMap } from '@/lib/map/createMap'
  import BasemapToggle from '@/lib/map/BasemapToggle.svelte'
  import MapLayersButton from '@/lib/map/MapLayersButton.svelte'
  import { followRoads } from '@/lib/map/roads.svelte'

  import { addReferenceLayers, FIRST_REFERENCE_LAYER, type Reference, SYSTEM_FILTER } from './references'

  export type ShapeOnMap = {
    boundary: Boundary
    label: string
    state: 'skip' | 'field' | 'new'
    /** Where it goes, for the hover label ("Update East 40") */
    detail?: string
  }
  /** A saved field's outline; updatedBy names the shape replacing it */
  export type FieldOnMap = { name: string; boundary: Boundary; updatedBy: string | null }

  // The shapes from an outline file, named as in the list beside the map, over the operation's
  // saved fields (a layer, on to start with) and its systems. What's from the file is filled, in the
  // color of where it goes; what's saved in WISP is only outlined: fields in the map's field color, dashed when a
  // shape will replace one, and systems in their cyan, the only blue on the map. A legend in the
  // lower left corner; clicking a shape picks its row; beside the pointer, a label names the shapes,
  // fields and systems under it.
  let {
    shapes,
    fields = [],
    references,
    selected = null,
    onselect,
    fileKey = 0,
    height = '28rem',
    fill = false,
  }: {
    shapes: ShapeOnMap[]
    fields?: FieldOnMap[]
    /** Changes with each file read, to fit the map to its shapes */
    fileKey?: number
    references: Reference[]
    selected?: number | null
    onselect?: (index: number) => void
    height?: string
    /** Fills its box's height (at least 24rem) in place of a fixed height */
    fill?: boolean
  } = $props()

  // The same in both themes, as the basemaps are
  const palette = readPalette()
  const colors: Record<ShapeOnMap['state'], string> = {
    new: palette.shapeNew,
    field: palette.shapeUpdate,
    skip: palette.shapeSkip,
  }
  // Line widths in pixels: where a shape goes heavier than what's skipped or already saved
  const WIDTHS = { skip: 1.25, saved: 1.5, field: 3, new: 3, selected: 4.5 }
  // Fill opacity: a skipped shape fainter; the selected one stronger
  const FILLS = { skip: 0.15, field: 0.3, new: 0.3, selected: 0.5 }

  type Swatch = { label: string; color: string; width: number; filled?: boolean; dashed?: boolean; round?: boolean }
  const SHAPE_LEGEND: Swatch[] = [
    { label: 'Skip', color: colors.skip, width: WIDTHS.skip, filled: true },
    { label: 'New field', color: colors.new, width: WIDTHS.new, filled: true },
    { label: 'Update field', color: colors.field, width: WIDTHS.field, filled: true },
  ]
  const FIELD_LEGEND: Swatch[] = [
    { label: 'Saved field', color: palette.field, width: WIDTHS.saved },
    { label: 'Field to update', color: palette.field, width: WIDTHS.saved, dashed: true },
  ]
  const SYSTEM_SWATCH: Swatch = { label: 'Irrigation system', color: palette.system, width: 2, round: true }

  let container: HTMLDivElement
  let map = $state<MapLibreMap>()
  followRoads(() => map)
  let basemap = $state<Basemap>('imagery')
  let fieldsOn = $state(true)
  const FIELD_LAYERS = ['fields-casing', 'fields-line', 'fields-updated', 'fields-hit']

  const fieldData = () => ({
    type: 'FeatureCollection' as const,
    features: fields.map((field) => ({
      type: 'Feature' as const,
      properties: {
        updated: field.updatedBy !== null,
        hover: `Field: ${field.name}${field.updatedBy === null ? '' : ` · updated from ${field.updatedBy}`}`,
      },
      geometry: field.boundary,
    })),
  })

  const data = () => ({
    type: 'FeatureCollection' as const,
    features: shapes.flatMap((shape, index) => [
      {
        type: 'Feature' as const,
        id: index,
        properties: {
          index,
          state: shape.state,
          selected: index === selected,
          label: '',
          hover: `Shape: ${shape.label}${shape.detail ? ` · ${shape.detail}` : ''}`,
        },
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

  // Drawn bottom to top in the order of what matters most: skipped shapes, saved fields, shapes
  // updating a field, new fields, then the irrigation systems over every field, and the shapes'
  // names over everything. MapLibre draws layers in the order they're added.
  const SHAPE_TIERS = ['skip', 'field', 'new'] as const
  const SHAPE_FILLS = SHAPE_TIERS.map((state) => `shapes-${state}-fill`)

  function addShapeTier(m: MapLibreMap, state: ShapeOnMap['state']) {
    const filter: ExpressionSpecification = ['all', ['!=', ['geometry-type'], 'Point'], ['==', ['get', 'state'], state]]
    m.addLayer({
      id: `shapes-${state}-fill`,
      type: 'fill',
      source: 'shapes',
      filter,
      paint: {
        'fill-color': colors[state],
        'fill-opacity': ['case', ['get', 'selected'], FILLS.selected, FILLS[state]],
      },
    })
    m.addLayer({
      id: `shapes-${state}-line`,
      type: 'line',
      source: 'shapes',
      filter,
      paint: {
        'line-color': colors[state],
        'line-width': ['case', ['get', 'selected'], WIDTHS.selected, WIDTHS[state]],
      },
    })
  }

  function addLayers(m: MapLibreMap) {
    m.addSource('shapes', { type: 'geojson', data: data() as never })
    m.addSource('fields', { type: 'geojson', data: fieldData() as never })

    addShapeTier(m, 'skip')

    // Saved fields: on a thin dark casing (for the street map), dashed where a shape will replace the outline
    const visibility = fieldsOn ? 'visible' : 'none'
    const isUpdated: ExpressionSpecification = ['get', 'updated']
    m.addLayer({
      id: 'fields-hit',
      type: 'fill',
      source: 'fields',
      layout: { visibility },
      paint: { 'fill-opacity': 0 },
    })
    m.addLayer({
      id: 'fields-casing',
      type: 'line',
      source: 'fields',
      filter: ['!', isUpdated],
      layout: { visibility },
      paint: { 'line-color': palette.fieldCasing, 'line-width': WIDTHS.saved + 1.5, 'line-opacity': 0.35 },
    })
    m.addLayer({
      id: 'fields-line',
      type: 'line',
      source: 'fields',
      filter: ['!', isUpdated],
      layout: { visibility },
      paint: { 'line-color': palette.field, 'line-width': WIDTHS.saved, 'line-opacity': 0.85 },
    })
    m.addLayer({
      id: 'fields-updated',
      type: 'line',
      source: 'fields',
      filter: isUpdated,
      layout: { visibility },
      paint: { 'line-color': palette.field, 'line-width': WIDTHS.saved, 'line-dasharray': [2, 1.5] },
    })

    addShapeTier(m, 'field')
    addShapeTier(m, 'new')

    addReferenceLayers(m, references, { ownFirst: false })
    // The systems' outlines, unseen, so hovering anywhere inside one names it
    m.addLayer(
      { id: 'reference-hit', type: 'fill', source: 'reference', filter: SYSTEM_FILTER, paint: { 'fill-opacity': 0 } },
      FIRST_REFERENCE_LAYER,
    )

    m.addLayer({
      id: 'shapes-label',
      type: 'symbol',
      source: 'shapes',
      filter: ['==', ['geometry-type'], 'Point'],
      layout: { 'text-field': ['get', 'label'], 'text-size': 13, 'text-font': LABEL_FONT },
      paint: labelPaint(1.5),
    })
    // A click picks the topmost shape under it
    m.on('click', (event) => {
      const [shape] = m.queryRenderedFeatures(event.point, { layers: SHAPE_FILLS })
      const index = shape?.properties?.index
      if (typeof index === 'number') onselect?.(index)
    })
  }

  // The hover label follows the pointer, worked out once a frame from the last pointer event: the
  // shapes under it, then the systems (a point kind's dot, or anywhere inside an outline), then the
  // saved fields while they're shown
  let wrapper: HTMLDivElement
  let hover = $state<{ x: number; y: number; lines: string[]; flip: boolean } | null>(null)
  let lastPointer: PointerEvent | null = null
  let frame = 0
  function onPointer(event: PointerEvent) {
    lastPointer = event
    frame ||= requestAnimationFrame(updateHover)
  }
  function updateHover() {
    frame = 0
    const m = map
    const event = lastPointer
    if (!m || !event || event.buttons) return (hover = null)
    const box = m.getCanvasContainer().getBoundingClientRect()
    const point: [number, number] = [event.clientX - box.left, event.clientY - box.top]
    const lines = (layers: string[], line: (properties: Record<string, unknown>) => string) =>
      m
        .queryRenderedFeatures(point, { layers: layers.filter((id) => m.getLayer(id)) })
        .map((feature) => line(feature.properties))
    const shapesHere = lines(SHAPE_FILLS, (properties) => String(properties.hover))
    // A pointer where a click picks a shape
    m.getCanvas().style.cursor = shapesHere.length ? 'pointer' : ''
    const found = [
      ...new Set([
        ...shapesHere,
        ...lines(['reference-dot', 'reference-hit'], (properties) => `System: ${properties.hoverName}`),
        ...lines(['fields-hit'], (properties) => String(properties.hover)),
      ]),
    ]
    const frameBox = wrapper.getBoundingClientRect()
    const x = event.clientX - frameBox.left
    hover = found.length ? { x, y: event.clientY - frameBox.top, lines: found, flip: x > frameBox.width - 340 } : null
  }

  const basemapSwitch = new BasemapSwitch(
    untrack(() => basemap),
    {
      map: () => map,
      isOwn: (id) => id === 'reference' || id === 'shapes' || id === 'fields',
      show: (to) => (basemap = to),
    },
  )

  onMount(() => {
    const remove = createMap(container, basemap, (m) =>
      m.on('load', () => {
        map = m
        addLayers(m)
        fit()
        const canvasContainer = m.getCanvasContainer()
        canvasContainer.addEventListener('pointermove', onPointer)
        canvasContainer.addEventListener('pointerleave', () => {
          lastPointer = null
          hover = null
        })
        // Recomputed as the map moves under a still pointer
        m.on('moveend', () => lastPointer && onPointer(lastPointer))
      }),
    )
    return () => {
      cancelAnimationFrame(frame)
      remove()
    }
  })

  // A changed choice or selection recolors the shapes; a new file (fileKey) also fits the map to them
  $effect(() => {
    void [shapes, selected]
    untrack(() => {
      map?.getSource<GeoJSONSource>('shapes')?.setData(data() as never)
      // The label says where a shape goes now
      if (lastPointer) onPointer(lastPointer)
    })
  })
  $effect(() => {
    void fields
    untrack(() => map?.getSource<GeoJSONSource>('fields')?.setData(fieldData() as never))
  })
  $effect(() => {
    const visibility = fieldsOn ? 'visible' : 'none'
    untrack(() => {
      const m = map
      if (!m) return
      for (const id of FIELD_LAYERS) if (m.getLayer(id)) m.setLayoutProperty(id, 'visibility', visibility)
    })
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

{#snippet legendItem(swatch: Swatch)}
  <!-- Drawn as on the map: a dark tile like the imagery, the outline's line (dashed as the map's
       dashes, at this size) and a filled shape's tint -->
  <span class="inline-flex items-center gap-1">
    <svg viewBox="0 0 22 16" class="h-4 w-[1.375rem] shrink-0" aria-hidden="true">
      <rect width="22" height="16" rx="2" fill="#2f3a2c" />
      {#if swatch.round}
        <circle cx="11" cy="8" r="5" fill="none" stroke="#0c2d48" stroke-width="3.5" />
        <circle cx="11" cy="8" r="5" fill="none" stroke={swatch.color} stroke-width="2" />
      {:else}
        <rect
          x="4"
          y="3.5"
          width="14"
          height="9"
          fill={swatch.filled ? swatch.color : 'none'}
          fill-opacity={swatch.filled ? 0.35 : undefined}
          stroke={swatch.color}
          stroke-width={swatch.width * 0.75}
          stroke-dasharray={swatch.dashed ? '3 2.5' : undefined}
        />
      {/if}
    </svg>{swatch.label}
  </span>
{/snippet}

<div class="flex flex-col {fill ? 'h-full' : ''}">
  <div
    bind:this={wrapper}
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
      <MapLayersButton id="import-map-layers" {basemap} count={fieldsOn && fields.length ? 1 : 0}>
        {#if fields.length}
          <label class="flex items-start gap-2">
            <input type="checkbox" class="mt-1" bind:checked={fieldsOn} />
            <span>
              Saved fields
              <span class="block text-xs text-ink-muted"
                >Your fields' shapes in WISP, dashed where a shape will update one</span
              >
            </span>
          </label>
        {/if}
      </MapLayersButton>
    </div>
    <!-- The legend, over the map's lower left corner (the attribution is at the right). Each swatch
         is on a dark tile, as the shapes are on the imagery -->
    <div
      class="pointer-events-none absolute bottom-2 left-2 max-w-[calc(100%-4rem)] space-y-0.5 rounded-md
        bg-surface-raised/90 px-2 py-1 text-xs text-ink shadow-md ring-1 ring-line"
    >
      <p class="flex flex-wrap gap-x-3">
        {#each SHAPE_LEGEND as swatch (swatch.label)}{@render legendItem(swatch)}{/each}
      </p>
      <p class="flex flex-wrap gap-x-3">
        {#if fieldsOn && fields.length}
          {#each FIELD_LEGEND as swatch (swatch.label)}{@render legendItem(swatch)}{/each}
        {/if}
        {@render legendItem(SYSTEM_SWATCH)}
      </p>
    </div>
    {#if hover}
      <!-- Pointer users only: the cards and the skipped shapes' table name everything for keyboards and screen readers -->
      <div
        class="pointer-events-none absolute z-10 w-max max-w-80 space-y-0.5 rounded-md bg-surface-raised px-2 py-1 text-xs
          text-ink shadow-md ring-1 ring-line {hover.flip ? '-translate-x-full' : ''}"
        style:left="{hover.flip ? hover.x - 12 : hover.x + 14}px"
        style:top="{hover.y + 16}px"
        aria-hidden="true"
      >
        {#each hover.lines as line, index (index)}
          <p>{line}</p>
        {/each}
      </div>
    {/if}
  </div>
</div>
