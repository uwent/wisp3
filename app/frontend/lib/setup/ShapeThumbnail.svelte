<script lang="ts">
  import { type Boundary, boundaryRing } from '@/lib/geo'

  // A field's outline drawn small (PLAN.md Phase 8 G.14, the field dialog's Shape): longitude
  // scaled by cos(latitude) so it keeps its proportions, north up
  let { boundary, size = 64, label }: { boundary: Boundary; size?: number; label: string } = $props()

  const drawing = $derived.by(() => {
    const ring = boundaryRing(boundary)
    const lats = ring.map(([, lat]) => lat)
    const scale = Math.cos((((Math.min(...lats) + Math.max(...lats)) / 2) * Math.PI) / 180)
    const points = ring.map(([lng, lat]) => [lng * scale, -lat])
    const xs = points.map(([x]) => x)
    const ys = points.map(([, y]) => y)
    const [minX, minY] = [Math.min(...xs), Math.min(...ys)]
    const span = Math.max(Math.max(...xs) - minX, Math.max(...ys) - minY) || 1
    // Into a 100 × 100 box with a margin, centered
    const fit = 90 / span
    const dx = 5 + (90 - (Math.max(...xs) - minX) * fit) / 2
    const dy = 5 + (90 - (Math.max(...ys) - minY) * fit) / 2
    const d = points
      .map(([x, y], i) => `${i ? 'L' : 'M'}${((x - minX) * fit + dx).toFixed(1)} ${((y - minY) * fit + dy).toFixed(1)}`)
      .join(' ')
    return `${d} Z`
  })
</script>

<svg
  viewBox="0 0 100 100"
  width={size}
  height={size}
  role="img"
  aria-label={label}
  class="shrink-0 rounded border border-line bg-surface"
>
  <path
    d={drawing}
    class="fill-map-system/25 stroke-map-system"
    stroke-width="2"
    stroke-linejoin="round"
    vector-effect="non-scaling-stroke"
  />
</svg>
