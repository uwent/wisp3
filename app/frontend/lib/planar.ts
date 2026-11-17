// Plane geometry on [x, y] pairs in any units: pixels (map glyphs), meters (an outline projected
// around itself) or degrees (longitude and latitude across a farm, plenty for which side or crossing)

type XY = readonly number[]

/** Which side of the line p→q the point r is on: 1 to the left, -1 to the right, 0 on it */
export const side = (p: XY, q: XY, r: XY) => Math.sign((q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0]))

/** How far along the segment a→b (0 to 1) its point nearest p is */
export function nearestT(p: XY, a: XY, b: XY): number {
  const dx = b[0] - a[0]
  const dy = b[1] - a[1]
  const length2 = dx * dx + dy * dy
  return length2 ? Math.max(0, Math.min(1, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / length2)) : 0
}

/** A point's distance from the segment a–b */
export function segmentDistance(p: XY, a: XY, b: XY): number {
  const t = nearestT(p, a, b)
  return Math.hypot(p[0] - a[0] - t * (b[0] - a[0]), p[1] - a[1] - t * (b[1] - a[1]))
}

/** Whether the segments a–b and c–d cross. touching: whether meeting at a point (an end on the other, or in a line) counts */
export function segmentsCross(a: XY, b: XY, c: XY, d: XY, { touching = false } = {}): boolean {
  if (touching) return side(a, b, c) !== side(a, b, d) && side(c, d, a) !== side(c, d, b)
  return side(a, b, c) * side(a, b, d) < 0 && side(c, d, a) * side(c, d, b) < 0
}
