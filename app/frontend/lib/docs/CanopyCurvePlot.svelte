<script lang="ts">
  // A crop's percent cover curve by day since emergence, for its card on the About page: gridlines at
  // 50% and 80% (where crop ET reaches reference ET) and a tick every 30 days
  let { covers, label }: { covers: number[]; label: string } = $props()

  const width = 280
  const height = 120
  const left = 30
  const bottom = 18
  const top = 6
  const right = 8
  const days = $derived(covers.length - 1)
  const x = (day: number) => left + (day / (days || 1)) * (width - left - right)
  const y = (pct: number) => top + (1 - pct / 100) * (height - top - bottom)
  const path = $derived(
    covers.map((cover, day) => `${day ? 'L' : 'M'}${x(day).toFixed(1)},${y(cover).toFixed(1)}`).join(''),
  )
  const ticks = $derived(Array.from({ length: Math.floor(days / 30) + 1 }, (_, i) => i * 30))
</script>

<svg viewBox="0 0 {width} {height}" class="h-auto w-full" role="img" aria-label={label}>
  {#each [0, 50, 80, 100] as pct (pct)}
    <line
      x1={left}
      x2={width - right}
      y1={y(pct)}
      y2={y(pct)}
      class="stroke-line"
      stroke-width="1"
      stroke-dasharray={pct === 0 ? undefined : '3 3'}
    />
    <text x={left - 4} y={y(pct) + 3} text-anchor="end" class="fill-ink-muted text-[9px]">{pct}%</text>
  {/each}
  {#each ticks as day (day)}
    <text x={x(day)} y={height - 4} text-anchor="middle" class="fill-ink-muted text-[9px]">{day}</text>
  {/each}
  <path d={path} fill="none" stroke="var(--color-chart-canopy)" stroke-width="2" stroke-linejoin="round" />
</svg>
