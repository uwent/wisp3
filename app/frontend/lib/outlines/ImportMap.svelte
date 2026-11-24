<script lang="ts">
  import 'maplibre-gl/dist/maplibre-gl.css'

  import { onMount, untrack } from 'svelte'
  import type { GeoJSONSource, Map as MapLibreMap } from 'maplibre-gl'

  import { readPalette } from '@/lib/charts/palette'
  import { boundsOf } from '@/lib/geo'
  import { type Boundary, boundaryBounds, boundaryCenter } from '@/lib/boundary'
  import { type Basemap, BasemapSwitch, LABEL_FONT, labelPaint } from '@/lib/map/basemaps'
  import { createMap } from '@/lib/map/createMap'
  import BasemapToggle from '@/lib/map/BasemapToggle.svelte'
  import MapLayersButton from '@/lib/map/MapLayersButton.svelte'
  import MapLegend from '@/lib/map/MapLegend.svelte'
  import HoverLabel from '@/lib/map/HoverLabel.svelte'
  import { MapHover, propertiesAt } from '@/lib/map/hover.svelte'
  import { followRoads } from '@/lib/map/roads.svelte'

  import {
    addSavedFieldLayers,
    addShapeTier,
    SAVED_FIELD_LAYERS,
    SAVED_FIELD_SOURCE,
    type SavedField,
    savedFieldData,
    type ShapeState,
    shapeTierLayers,
    swatches,
  } from './layers'
  import { addReferenceLayers, type Reference, SYSTEM_HOVER_LAYERS } from './references'
  import { showLayers } from '@/lib/map/maplibre'

  export type ShapeOnMap = {
    boundary: Boundary
    label: string
    state: ShapeState
    /** Where it goes, for the hover label ("Update East 40") */
    detail?: string
  }
  // The shapes from an outline file, named as in the list beside the map, over the operation's
  // saved fields (a layer, on to start with) and its systems, in the setup maps' symbology
  // (lib/outlines/layers.ts). A legend in the lower left corner; clicking a shape picks its row;
  // beside the pointer, a label names the shapes, fields and systems under it.
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
    fields?: SavedField[]
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
  const legend = swatches(palette)

  let container: HTMLDivElement
  let map = $state<MapLibreMap>()
  followRoads(() => map)
  let basemap = $state<Basemap>('imagery')
  let fieldsOn = $state(true)

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

  // Bottom to top by what matters most: skipped shapes, saved fields, shapes updating a field, new
  // fields, the systems over every field, and the shapes' names over everything
  const SHAPE_FILLS = (['skip', 'field', 'new'] as const).map((state) => shapeTierLayers('shapes', state)[0])

  function addLayers(m: MapLibreMap) {
    m.addSource('shapes', { type: 'geojson', data: data() as never })
    addShapeTier(m, palette, 'shapes', 'skip')
    addSavedFieldLayers(m, palette, fields, fieldsOn)
    addShapeTier(m, palette, 'shapes', 'field')
    addShapeTier(m, palette, 'shapes', 'new')

    addReferenceLayers(m, references, { ownFirst: false })

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

  // Beside the pointer: the shapes under it, then the systems (a point kind's dot, or anywhere inside
  // an outline), then the saved fields while they're shown
  let wrapper = $state<HTMLDivElement>()
  const hover = new MapHover(
    (m, point) => {
      const shapesHere = propertiesAt(m, point, SHAPE_FILLS).map((properties) => String(properties.hover))
      // A pointer where a click picks a shape
      m.getCanvas().style.cursor = shapesHere.length ? 'pointer' : ''
      return [
        ...new Set([
          ...shapesHere,
          ...propertiesAt(m, point, SYSTEM_HOVER_LAYERS).map((properties) => `System: ${properties.hoverName}`),
          ...propertiesAt(m, point, ['saved-fields-hit']).map((properties) => String(properties.hover)),
        ]),
      ]
    },
    () => wrapper,
  )

  const basemapSwitch = new BasemapSwitch(
    untrack(() => basemap),
    {
      map: () => map,
      isOwn: (id) => id === 'reference' || id === 'shapes' || id === SAVED_FIELD_SOURCE,
      show: (to) => (basemap = to),
    },
  )

  let stopHover = () => {}
  onMount(() => {
    const remove = createMap(container, basemap, (m) =>
      m.on('load', () => {
        map = m
        addLayers(m)
        fit()
        stopHover = hover.attach(m)
      }),
    )
    return () => {
      stopHover()
      remove()
    }
  })

  // A changed choice or selection recolors the shapes; a new file (fileKey) also fits the map to them
  $effect(() => {
    void [shapes, selected]
    untrack(() => {
      map?.getSource<GeoJSONSource>('shapes')?.setData(data() as never)
      // The label says where a shape goes now, once the map has drawn the new data
      map?.once('idle', () => hover.refresh())
    })
  })
  $effect(() => {
    void fields
    untrack(() => map?.getSource<GeoJSONSource>(SAVED_FIELD_SOURCE)?.setData(savedFieldData(fields) as never))
  })
  $effect(() => {
    const on = fieldsOn
    untrack(() => showLayers(map, SAVED_FIELD_LAYERS, on))
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

<div class="flex flex-col {fill ? 'h-full' : ''}">
  <div
    bind:this={wrapper}
    class="relative overflow-hidden rounded-lg border border-line {fill ? 'min-h-96 flex-1' : ''}"
    style:height={fill ? undefined : height}
  >
    <div
      bind:this={container}
      class="size-full"
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
    <MapLegend
      rows={[
        [legend.skip, legend.new, legend.field],
        [
          ...(fieldsOn && fields.length ? [legend.saved] : []),
          ...(fieldsOn && fields.some((field) => field.updatedBy) ? [legend.updated] : []),
          ...(references.length ? [legend.system] : []),
        ],
      ]}
    />
    <HoverLabel label={hover.label} />
  </div>
</div>
