import { EARTH_RADIUS_M, type LngLat, pointInPolygon } from '@/lib/geo'
import { type Boundary, boundaryBounds, boundaryRing, ringAreaM2 } from '@/lib/boundary'
import { segmentDistance } from '@/lib/planar'

// How much two field outlines overlap, to catch a shape that's already a field (an import's
// duplicate, or two saved fields drawn over each other). Estimated on a grid of points over the
// box the two share, which is accurate to a few percent: plenty to say "overlaps 85%", without a
// polygon clipping library.

/** Points per side of the grid over the shared box */
const GRID = 24

/** An overlap this large (of the smaller outline) is the same field: an import updates it */
export const SAME_FIELD_SHARE = 0.5
/** An overlap this large is worth a warning; less is two neighbors' edges disagreeing a little */
export const OVERLAP_WARNING_SHARE = 0.1

type Box = [LngLat, LngLat]

const M_PER_DEG = 111_320

const boxesMeet = ([aMin, aMax]: Box, [bMin, bMax]: Box) =>
  aMin[0] <= bMax[0] && bMin[0] <= aMax[0] && aMin[1] <= bMax[1] && bMin[1] <= aMax[1]

/**
 * The share of the smaller outline's area that the other covers, from 0 to 1. Outlines whose boxes
 * don't meet are 0 without sampling. Boxes can be passed in when they're already known.
 */
export function overlapShare(
  a: Boundary,
  b: Boundary,
  boxA: Box = boundaryBounds(a),
  boxB = boundaryBounds(b),
): number {
  if (!boxesMeet(boxA, boxB)) return 0
  const west = Math.max(boxA[0][0], boxB[0][0])
  const east = Math.min(boxA[1][0], boxB[1][0])
  const south = Math.max(boxA[0][1], boxB[0][1])
  const north = Math.min(boxA[1][1], boxB[1][1])
  if (east <= west || north <= south) return 0
  const [ringA, ringB] = [boundaryRing(a), boundaryRing(b)]
  let inBoth = 0
  for (let i = 0; i < GRID; i++) {
    const lng = west + ((i + 0.5) / GRID) * (east - west)
    for (let j = 0; j < GRID; j++) {
      const point: LngLat = [lng, south + ((j + 0.5) / GRID) * (north - south)]
      if (pointInPolygon(point, [ringA]) && pointInPolygon(point, [ringB])) inBoth++
    }
  }
  if (!inBoth) return 0
  const middle = (south + north) / 2
  const boxM2 = (east - west) * Math.cos((middle * Math.PI) / 180) * M_PER_DEG * (north - south) * M_PER_DEG
  const sharedM2 = (inBoth / GRID ** 2) * boxM2
  const smaller = Math.min(ringAreaM2(ringA), ringAreaM2(ringB))
  return smaller > 0 ? Math.min(sharedM2 / smaller, 1) : 0
}

export type Outline = { id: number; boundary: Boundary }

/** Outlines with their boxes, worked out once to test against many shapes */
export const withBoxes = <T extends Outline>(outlines: T[]) =>
  outlines.map((outline) => ({ outline, box: boundaryBounds(outline.boundary) }))

/** The pairs of outlines that overlap by at least `least`, each pair once, largest first */
export function overlappingPairs<T extends Outline>(
  outlines: T[],
  least = OVERLAP_WARNING_SHARE,
): { a: T; b: T; share: number }[] {
  const boxed = withBoxes(outlines)
  const pairs: { a: T; b: T; share: number }[] = []
  for (let i = 0; i < boxed.length; i++)
    for (let j = i + 1; j < boxed.length; j++) {
      const share = overlapShare(boxed[i].outline.boundary, boxed[j].outline.boundary, boxed[i].box, boxed[j].box)
      if (share >= least) pairs.push({ a: boxed[i].outline, b: boxed[j].outline, share })
    }
  return pairs.sort((x, y) => y.share - x.share)
}

/**
 * Outlines this close (outlineDifferenceM) are the same shape: a file read again, or the same field
 * boundary exported from another program. About 10 ft, inside a GPS's error and a boundary line's
 * width on the imagery; a field redrawn or a corner moved is farther.
 */
export const SAME_OUTLINE_M = 3

/**
 * How far apart two outlines are, in meters: the farthest a corner of either lies from the other's
 * edge (their Hausdorff distance, near enough: a field's corners are where outlines part). 0 for the
 * same outline, whichever corner it starts at or way it runs. The overlap's grid can't tell the
 * same shape from one a few percent off, so this, exact, decides whether a shape is already a field's.
 */
export function outlineDifferenceM(a: Boundary, b: Boundary): number {
  const [ringA, ringB] = [boundaryRing(a), boundaryRing(b)]
  // Plane coordinates in meters around the first outline, plenty at a field's scale
  const [lng0, lat0] = ringA[0]
  const cos = Math.cos((lat0 * Math.PI) / 180)
  const toM = ([lng, lat]: LngLat) => [
    (((lng - lng0) * Math.PI) / 180) * cos * EARTH_RADIUS_M,
    (((lat - lat0) * Math.PI) / 180) * EARTH_RADIUS_M,
  ]
  const [xyA, xyB] = [ringA.map(toM), ringB.map(toM)]
  const farthest = (corners: number[][], ring: number[][]) => {
    let most = 0
    for (const corner of corners) {
      let nearest = Infinity
      for (let i = 0; i + 1 < ring.length && nearest > most; i++) {
        nearest = Math.min(nearest, segmentDistance(corner, ring[i], ring[i + 1]))
      }
      most = Math.max(most, nearest)
    }
    return most
  }
  return Math.max(farthest(xyA, xyB), farthest(xyB, xyA))
}

/** "85%" (a sliver rounds up to 1%) */
export const sharePercent = (share: number) => `${Math.max(1, Math.round(share * 100))}%`
