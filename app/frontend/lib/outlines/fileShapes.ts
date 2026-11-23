import { type Boundary, boundaryBounds } from '@/lib/boundary'

import type { KeptFile } from './kept'
import { outlineDifferenceM, SAME_OUTLINE_M } from './overlap'
import { shapeName } from './read'

// A kept outline file's shapes as a guide on the irrigation system map: those not yet any field's
// shape, named, so a grower can place each system on its fields before importing them in Setup.

export type FileShape = { name: string; boundary: Boundary }

export type FileShapes = { fileName: string; shapes: FileShape[] }

type Box = [[number, number], [number, number]]
const boxesMeet = ([aMin, aMax]: Box, [bMin, bMax]: Box) =>
  aMin[0] <= bMax[0] && bMin[0] <= aMax[0] && aMin[1] <= bMax[1] && bMin[1] <= aMax[1]

/**
 * The kept file's usable shapes that aren't already a saved field's (within SAME_OUTLINE_M of one
 * of outlines), each named by the file's name attribute; null when none are left
 */
export function unimportedShapes(kept: KeptFile, outlines: Boundary[]): FileShapes | null {
  const saved = outlines.map((boundary) => ({ boundary, box: boundaryBounds(boundary) as Box }))
  const shapes = kept.shapes.flatMap((shape): FileShape[] => {
    if (!shape.boundary || shape.problems.length) return []
    const boundary = shape.boundary
    const box = boundaryBounds(boundary) as Box
    const imported = saved.some(
      (outline) => boxesMeet(box, outline.box) && outlineDifferenceM(boundary, outline.boundary) <= SAME_OUTLINE_M,
    )
    return imported ? [] : [{ name: shapeName(shape, kept.nameKey), boundary }]
  })
  return shapes.length ? { fileName: kept.fileName, shapes } : null
}
