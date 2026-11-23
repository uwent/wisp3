import type { Map as MapLibreMap, PointLike } from 'maplibre-gl'

/** The hover label's lines at a point of the map (empty: no label) */
export type HoverLines = (map: MapLibreMap, point: PointLike) => string[]
/** A muted last line for the label: what a click at the point would do, or null */
export type HoverHint = (map: MapLibreMap, point: [number, number]) => string | null

/**
 * A setup map's hover label (HoverLabel.svelte): what's under the pointer, a line each, worked out
 * once a frame from the last pointer event, cleared on leaving or while dragging, and again as the
 * map moves under a still pointer or `refresh` is called (what a line says has changed). The label
 * sits beside the pointer, flipped to its left near the right edge of `box` (the map's box). `hint`
 * adds a muted last line under the others, what a click there would do.
 */
export class MapHover {
  label = $state<{ x: number; y: number; lines: string[]; hint: string | null; flip: boolean } | null>(null)
  #lastPointer: PointerEvent | null = null
  #frame = 0
  #map: MapLibreMap | undefined
  #box: () => HTMLElement | undefined

  #hint: HoverHint

  constructor(
    private lines: HoverLines,
    box: () => HTMLElement | undefined,
    hint: HoverHint = () => null,
  ) {
    this.#box = box
    this.#hint = hint
  }

  /** Follow the pointer over the map (once it's made); returns the cleanup */
  attach(map: MapLibreMap): () => void {
    this.#map = map
    const canvas = map.getCanvasContainer()
    const move = (event: PointerEvent) => this.#onPointer(event)
    const leave = () => {
      this.#lastPointer = null
      this.label = null
    }
    const moved = () => this.refresh()
    canvas.addEventListener('pointermove', move)
    canvas.addEventListener('pointerleave', leave)
    map.on('moveend', moved)
    return () => {
      cancelAnimationFrame(this.#frame)
      this.#frame = 0
      canvas.removeEventListener('pointermove', move)
      canvas.removeEventListener('pointerleave', leave)
      map.off('moveend', moved)
    }
  }

  /** Work the label out again where the pointer is */
  refresh() {
    if (this.#lastPointer) this.#onPointer(this.#lastPointer)
  }

  #onPointer(event: PointerEvent) {
    this.#lastPointer = event
    this.#frame ||= requestAnimationFrame(() => this.#update())
  }

  #update() {
    this.#frame = 0
    const map = this.#map
    const event = this.#lastPointer
    const box = this.#box()
    if (!map || !event || !box || event.buttons) {
      this.label = null
      return
    }
    const canvasBox = map.getCanvasContainer().getBoundingClientRect()
    const point: [number, number] = [event.clientX - canvasBox.left, event.clientY - canvasBox.top]
    const lines = this.lines(map, point)
    const frameBox = box.getBoundingClientRect()
    const x = event.clientX - frameBox.left
    this.label = lines.length
      ? { x, y: event.clientY - frameBox.top, lines, hint: this.#hint(map, point), flip: x > frameBox.width - 340 }
      : null
  }
}

/** The features' properties at a point, from those of layers the map has, topmost first */
export const propertiesAt = (map: MapLibreMap, point: PointLike, layers: string[]) =>
  map
    .queryRenderedFeatures(point, { layers: layers.filter((id) => map.getLayer(id)) })
    .map((feature) => feature.properties)
