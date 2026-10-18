import type { Map as MapLibreMap, MapMouseEvent, MapSourceDataEvent, RasterTileSource } from 'maplibre-gl'

import { type LngLat, pointInPolygon } from '@/lib/geo'

import { PIVOT_LAYER } from './OverviewMap.svelte'
import {
  type Bounds,
  DROUGHT_CATEGORIES,
  type DroughtData,
  droughtAt,
  droughtDate,
  droughtUrl,
  NONE_COLOR,
  OVERLAY_ORDER,
  type OverlayId,
  type OverlayValue,
  OVERLAYS,
  type RasterOverlay,
} from './overlays'

export type OverlayStatus = 'loading' | 'ready' | 'unavailable'

/** MapLibre's error event; tile errors name their source */
type MapError = { sourceId?: string; error?: { message?: string } }

const sourceId = (id: OverlayId) => `overlay-${id}`
const overlayOf = (source: string | undefined) => {
  const id = source?.startsWith('overlay-') ? source.slice('overlay-'.length) : null
  return OVERLAYS.some((overlay) => overlay.id === id) ? (id as OverlayId) : null
}
/** The light gray over the US under the overlays: where a layer has nothing */
const NONE_LAYER = 'overlay-none'
const NONE_OPACITY = 0.45
/** Hovering this long over one spot asks the layers for their values */
const HOVER_MS = 300

type Outline = { geometry: { coordinates: LngLat[][][] } }
let outline: Promise<Outline> | undefined
// A simplified outline of the US (us-atlas 3.0.1, from the Census Bureau's cartographic boundaries),
// loaded the first time a layer is shown
const loadOutline = () =>
  (outline ??= import('./us-outline.json').then((module) => module.default as unknown as Outline))

export type ProbeValue = OverlayValue | 'loading' | 'unavailable' | 'outside'
/** The shown layers' values at a point on the map, for the tooltip; x and y are in the map's pixels */
export type Probe = { x: number; y: number; items: { id: OverlayId; name: string; none: string; value: ProbeValue }[] }

/** Tile errors before an overlay with no tiles loaded counts as unavailable (one bad tile isn't) */
const ERRORS_TO_FAIL = 3
const NOTICE_MS = 7000

/**
 * The map's optional overlays (PLAN.md Phase 7 E): shows and hides them under the pivots, reloads
 * them on their schedule, and when a provider fails marks the overlay unavailable with a short
 * notice (once per overlay per visit) while the rest of the map carries on. Switching an overlay off
 * and on again retries it.
 */
export class MapOverlays {
  status: Partial<Record<OverlayId, OverlayStatus>> = $state({})
  /** When each overlay's data is for ("Radar at 3:20 PM"), where its provider says */
  times: Partial<Record<OverlayId, string | null>> = $state({})
  notice: string | null = $state(null)
  /** The Drought Monitor's polygons around the pivots, once loaded */
  drought: DroughtData | null = $state(null)
  /** What the shown layers have under the pointer or a tap, or null */
  probe: Probe | null = $state(null)

  #map?: MapLibreMap
  #shown: OverlayId[] = []
  #opacity: Partial<Record<OverlayId, number>> = {}
  #counts: Partial<Record<OverlayId, { errors: number; loaded: number }>> = {}
  #notified: OverlayId[] = []
  #timers: Partial<Record<OverlayId, ReturnType<typeof setInterval>>> = {}
  #noticeTimer?: ReturnType<typeof setTimeout>
  #droughtRequest?: AbortController
  #probeRequest?: AbortController
  #hoverTimer?: ReturnType<typeof setTimeout>

  constructor(private readonly droughtArea: () => Bounds) {}

  /** Connects to the map; again after a basemap change, which keeps our sources */
  attach(map: MapLibreMap) {
    if (this.#map === map) return this.sync(this.#shown, this.#opacity)
    this.#map = map
    map.on('error', (event) => this.#onError(event as MapError))
    map.on('sourcedata', (event: MapSourceDataEvent) => {
      const id = overlayOf(event.sourceId)
      if (id && event.tile) this.#loaded(id)
    })
    // Values under the mouse when it rests (on devices that hover), and where a tap lands off the pivots
    if (matchMedia('(hover: hover)').matches) {
      map.on('mousemove', (event) => {
        clearTimeout(this.#hoverTimer)
        if (this.probe) this.#clearProbe()
        this.#hoverTimer = setTimeout(() => this.probeAt(event), HOVER_MS)
      })
      map.on('mouseout', () => {
        clearTimeout(this.#hoverTimer)
        this.#clearProbe()
      })
    }
    map.on('click', (event) => {
      if (map.getLayer(PIVOT_LAYER) && map.queryRenderedFeatures(event.point, { layers: [PIVOT_LAYER] }).length) return
      this.probeAt(event)
    })
    map.on('movestart', () => this.#clearProbe())
    this.sync(this.#shown, this.#opacity)
  }

  /** Asks each shown layer for its value at a point */
  probeAt(event: Pick<MapMouseEvent, 'point' | 'lngLat'>) {
    const shown = OVERLAYS.filter((overlay) => this.#shown.includes(overlay.id))
    if (!shown.length) return this.#clearProbe()
    this.#probeRequest?.abort()
    const request = (this.#probeRequest = new AbortController())
    const at: LngLat = [event.lngLat.lng, event.lngLat.lat]
    this.probe = {
      x: event.point.x,
      y: event.point.y,
      items: shown.map((overlay) => ({ id: overlay.id, name: overlay.name, none: overlay.none, value: 'loading' })),
    }
    const probe = this.probe
    const set = (id: OverlayId, value: ProbeValue) => {
      if (this.#probeRequest !== request) return
      const item = probe.items.find((i) => i.id === id)
      if (item) item.value = value
    }
    loadOutline()
      .then(({ geometry }) => geometry.coordinates.some((polygon) => pointInPolygon(at, polygon)))
      .catch(() => true)
      .then((inside) => {
        for (const overlay of shown) {
          if (!inside) set(overlay.id, 'outside')
          else if (overlay.kind === 'drought') set(overlay.id, this.#droughtValue(at))
          else
            overlay
              .valueAt(at, request.signal)
              .then((value) => set(overlay.id, value))
              .catch((error: Error) => error.name !== 'AbortError' && set(overlay.id, 'unavailable'))
        }
      })
  }

  #droughtValue(at: LngLat): ProbeValue {
    if (!this.drought) return this.status.drought === 'unavailable' ? 'unavailable' : 'loading'
    const category = droughtAt(this.drought, at)
    return category ? { kind: 'text', text: category.label, color: category.color } : { kind: 'none' }
  }

  #clearProbe() {
    this.#probeRequest?.abort()
    this.#probeRequest = undefined
    this.probe = null
  }

  /** Shows these overlays (at their opacity, or the default) and hides the rest */
  sync(shown: OverlayId[], opacity: Partial<Record<OverlayId, number>>) {
    this.#shown = shown
    this.#opacity = opacity
    const map = this.#map
    if (!map) return
    try {
      for (const overlay of OVERLAYS) {
        if (!shown.includes(overlay.id)) this.#hide(overlay.id)
        else if (overlay.kind === 'raster') this.#showRaster(map, overlay)
        else this.#showDrought(map)
      }
      if (shown.length) this.#showNone(map)
      else this.#hideNone(map)
    } catch {
      // The style is still loading (a basemap change): try again when it's done
      map.once('idle', () => this.sync(this.#shown, this.#opacity))
    }
  }

  destroy() {
    clearTimeout(this.#hoverTimer)
    this.#probeRequest?.abort()
    Object.values(this.#timers).forEach((timer) => clearInterval(timer))
    this.#timers = {}
    clearTimeout(this.#noticeTimer)
    this.#droughtRequest?.abort()
  }

  #opacityOf(id: OverlayId) {
    return this.#opacity[id] ?? OVERLAYS.find((overlay) => overlay.id === id)!.opacity
  }

  /** The layer to insert under: the next overlay up that's shown, or the pivots */
  #before(map: MapLibreMap, id: OverlayId) {
    const above = OVERLAY_ORDER.slice(OVERLAY_ORDER.indexOf(id) + 1).map(sourceId)
    return above.find((layer) => map.getLayer(layer)) ?? (map.getLayer(PIVOT_LAYER) ? PIVOT_LAYER : undefined)
  }

  #showRaster(map: MapLibreMap, overlay: RasterOverlay) {
    const id = sourceId(overlay.id)
    if (!map.getSource(id)) {
      this.#start(overlay.id)
      map.addSource(id, {
        type: 'raster',
        tiles: overlay.tiles(Date.now()),
        tileSize: 256,
        attribution: overlay.attribution,
      })
      this.#loadTime(overlay.id)
      if (overlay.refreshMinutes) {
        const timer = setInterval(() => this.#refresh(overlay), overlay.refreshMinutes * 60_000)
        this.#timers[overlay.id] = timer
      }
    }
    if (map.getLayer(id)) {
      map.setPaintProperty(id, 'raster-opacity', this.#opacityOf(overlay.id))
    } else {
      map.addLayer(
        {
          id,
          type: 'raster',
          source: id,
          paint: { 'raster-opacity': this.#opacityOf(overlay.id), 'raster-fade-duration': 0 },
        },
        this.#before(map, overlay.id),
      )
    }
  }

  /** The gray "none" over the US, under every overlay */
  #showNone(map: MapLibreMap) {
    if (map.getLayer(NONE_LAYER)) return
    loadOutline()
      .then((us) => {
        if (!this.#shown.length || map.getLayer(NONE_LAYER)) return
        if (!map.getSource(NONE_LAYER)) map.addSource(NONE_LAYER, { type: 'geojson', data: us as never })
        const lowest = OVERLAY_ORDER.map(sourceId).find((layer) => map.getLayer(layer))
        map.addLayer(
          {
            id: NONE_LAYER,
            type: 'fill',
            source: NONE_LAYER,
            paint: { 'fill-color': NONE_COLOR, 'fill-opacity': NONE_OPACITY },
          },
          lowest ?? (map.getLayer(PIVOT_LAYER) ? PIVOT_LAYER : undefined),
        )
      })
      .catch(() => {
        // Without the outline there's no gray; the layers still work
      })
  }

  #hideNone(map: MapLibreMap) {
    if (map.getLayer(NONE_LAYER)) map.removeLayer(NONE_LAYER)
    if (map.getSource(NONE_LAYER)) map.removeSource(NONE_LAYER)
    this.#clearProbe()
  }

  #refresh(overlay: RasterOverlay) {
    const source = this.#map?.getSource<RasterTileSource>(sourceId(overlay.id))
    if (!source) return
    this.#counts[overlay.id] = { errors: 0, loaded: 0 }
    source.setTiles(overlay.tiles(Date.now()))
    this.#loadTime(overlay.id)
  }

  #loadTime(id: OverlayId) {
    const overlay = OVERLAYS.find((o) => o.id === id)
    overlay
      ?.time?.()
      .then((time) => (this.times[id] = time))
      .catch(() => (this.times[id] = null))
  }

  #showDrought(map: MapLibreMap) {
    const id = sourceId('drought')
    if (!this.drought) {
      this.#loadDrought()
      return
    }
    if (!map.getSource(id)) {
      map.addSource(id, {
        type: 'geojson',
        data: this.drought,
        attribution: OVERLAYS.find((o) => o.id === 'drought')!.attribution,
      })
    }
    const color: unknown[] = ['match', ['get', 'DM']]
    DROUGHT_CATEGORIES.forEach(({ dm, color: fill }) => color.push(dm, fill))
    color.push('rgba(0,0,0,0)')
    if (map.getLayer(id)) {
      map.setPaintProperty(id, 'fill-opacity', this.#opacityOf('drought'))
    } else {
      map.addLayer(
        {
          id,
          type: 'fill',
          source: id,
          paint: {
            'fill-color': color as never,
            'fill-opacity': this.#opacityOf('drought'),
            'fill-outline-color': 'rgba(80,60,0,0.5)',
          },
        },
        this.#before(map, 'drought'),
      )
    }
    this.status.drought = 'ready'
  }

  #loadDrought() {
    if (this.#droughtRequest) return
    this.status.drought = 'loading'
    this.#droughtRequest = new AbortController()
    fetch(droughtUrl(this.droughtArea()), { signal: this.#droughtRequest.signal })
      .then((response) => {
        if (!response.ok) throw new Error(`Drought Monitor: ${response.status}`)
        return response.json() as Promise<DroughtData>
      })
      .then((data) => {
        if (!Array.isArray(data?.features)) throw new Error('Drought Monitor: no features')
        this.drought = data
        const date = droughtDate(data)
        this.times.drought = date
          ? `Map for ${date.toLocaleDateString('en-US', { month: 'short', day: 'numeric', timeZone: 'UTC' })}`
          : null
        this.sync(this.#shown, this.#opacity)
      })
      .catch((error: Error) => {
        if (error.name !== 'AbortError') this.#fail('drought')
      })
      .finally(() => (this.#droughtRequest = undefined))
  }

  #hide(id: OverlayId) {
    const map = this.#map
    const source = sourceId(id)
    if (map?.getLayer(source)) map.removeLayer(source)
    if (map?.getSource(source)) map.removeSource(source)
    clearInterval(this.#timers[id])
    delete this.#timers[id]
    if (id === 'drought') this.#droughtRequest?.abort()
    // Drought data stays loaded for the visit; a failed load is retried when switched on again
    if (this.status[id] && !(id === 'drought' && this.drought)) delete this.status[id]
  }

  #start(id: OverlayId) {
    this.#counts[id] = { errors: 0, loaded: 0 }
    this.status[id] = 'loading'
  }

  #loaded(id: OverlayId) {
    const counts = this.#counts[id]
    if (counts) counts.loaded++
    if (this.status[id] !== 'ready') this.status[id] = 'ready'
  }

  #onError(event: MapError) {
    const id = overlayOf(event.sourceId)
    if (!id) {
      // A basemap tile that didn't load is common and harmless; anything else is worth a warning
      if (!event.sourceId) console.warn('Map:', event.error?.message ?? event)
      return
    }
    const counts = (this.#counts[id] ??= { errors: 0, loaded: 0 })
    counts.errors++
    if (counts.errors >= ERRORS_TO_FAIL && counts.loaded === 0) this.#fail(id)
  }

  #fail(id: OverlayId) {
    if (this.status[id] === 'unavailable') return
    this.status[id] = 'unavailable'
    if (this.#notified.includes(id)) return
    this.#notified.push(id)
    const name = OVERLAYS.find((overlay) => overlay.id === id)!.name
    this.notice = `${name} isn't loading right now. The rest of the map works; try it again later.`
    clearTimeout(this.#noticeTimer)
    this.#noticeTimer = setTimeout(() => (this.notice = null), NOTICE_MS)
  }

  /** Clears the notice (its close button) */
  dismiss() {
    this.notice = null
  }
}
