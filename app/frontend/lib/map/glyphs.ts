import type { PivotKind } from '@/lib/geo'

// Each kind of irrigation system's glyph (PLAN.md Phase 8 G.14): the shape it's drawn as on the map
// when it's a point (a traveler, a block, a location) or too small to see at its true size (a pivot,
// a linear), and in the list and legend (KindIcon). SVG paths in a 24 × 24 box, which the map's
// icons are drawn from too.

export type Glyph = 'circle' | 'rectangle' | 'diamond' | 'square' | 'pentagon' | 'triangle'

export const KIND_GLYPHS: Record<PivotKind, Glyph> = {
  center: 'circle',
  linear: 'rectangle',
  traveler: 'diamond',
  solid_set: 'square',
  drip: 'pentagon',
  point: 'triangle',
}

/** A regular polygon's path around the box's center, its first corner straight up */
function regular(corners: number, radius = 12, cy = 12): string {
  const points = Array.from({ length: corners }, (_, i) => {
    const angle = -Math.PI / 2 + (2 * Math.PI * i) / corners
    return `${(12 + radius * Math.cos(angle)).toFixed(2)} ${(cy + radius * Math.sin(angle)).toFixed(2)}`
  })
  return `M${points.join('L')}Z`
}

export const GLYPH_PATHS: Record<Glyph, string> = {
  circle: 'M0 12a12 12 0 1 0 24 0a12 12 0 1 0 -24 0Z',
  // A linear move is wider than it travels, drawn turned to its direction of travel
  rectangle: 'M0 5h24v14H0Z',
  diamond: 'M12 0L24 12L12 24L0 12Z',
  square: 'M2 2h20v20H2Z',
  // Centered a little low, so it sits in the box like the others
  pentagon: regular(5, 12.5, 13),
  triangle: regular(3, 13.5, 14.5),
}
