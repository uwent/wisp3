import type { PivotKind } from '@/lib/geo'

// Each kind of irrigation system's glyph (PLAN.md Phase 8 G.14): the shape it's drawn as on the map
// when it's a point (a traveler, a block, a location) or too small to see at its true size (a pivot,
// a linear), and in the list and legend (KindIcon). Each is a polygon in a 24 × 24 box centered on
// (12, 12), so a glyph drawn around a marker's badges stays centered on them; the SVG paths and the
// map's icons (an exact distance field, systemLayers.ts) are both made from its corners.

export type Glyph = 'circle' | 'rectangle' | 'diamond' | 'square' | 'pentagon' | 'triangle'

export const KIND_GLYPHS: Record<PivotKind, Glyph> = {
  center: 'circle',
  linear: 'rectangle',
  traveler: 'diamond',
  solid_set: 'square',
  drip: 'pentagon',
  point: 'triangle',
}

type Point = [number, number]

/** A regular polygon around the box's center, its first corner straight up */
function regular(corners: number, radius = 12): Point[] {
  return Array.from({ length: corners }, (_, i) => {
    const angle = -Math.PI / 2 + (2 * Math.PI * i) / corners
    return [12 + radius * Math.cos(angle), 12 + radius * Math.sin(angle)]
  })
}

export const GLYPH_CORNERS: Record<Glyph, Point[]> = {
  circle: regular(64),
  // A linear is wider than it travels, drawn turned to its direction of travel
  rectangle: [
    [0, 5],
    [24, 5],
    [24, 19],
    [0, 19],
  ],
  diamond: regular(4),
  square: [
    [2, 2],
    [22, 2],
    [22, 22],
    [2, 22],
  ],
  pentagon: regular(5),
  // Around its centroid, so its point reaches the top of the box and its base sits at 18
  triangle: regular(3),
}

const path = (corners: Point[]) => `M${corners.map(([x, y]) => `${x.toFixed(2)} ${y.toFixed(2)}`).join('L')}Z`

export const GLYPH_PATHS = Object.fromEntries(
  (Object.keys(GLYPH_CORNERS) as Glyph[]).map((glyph) => [glyph, path(GLYPH_CORNERS[glyph])]),
) as Record<Glyph, string>

/**
 * The largest circle around the box's center inside the glyph, as a share of the box: a glyph S
 * pixels across holds a circle S × this in radius (the nearest edge's distance from the center)
 */
export const GLYPH_INRADIUS = Object.fromEntries(
  (Object.keys(GLYPH_CORNERS) as Glyph[]).map((glyph) => {
    const corners = GLYPH_CORNERS[glyph]
    const nearest = Math.min(...corners.map((a, i) => segmentDistance([12, 12], a, corners[(i + 1) % corners.length])))
    return [glyph, nearest / 24]
  }),
) as Record<Glyph, number>

/** A point's distance from the segment a–b */
export function segmentDistance([px, py]: Point, [ax, ay]: Point, [bx, by]: Point): number {
  const dx = bx - ax
  const dy = by - ay
  const t = Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy || 1)))
  return Math.hypot(px - ax - t * dx, py - ay - t * dy)
}
