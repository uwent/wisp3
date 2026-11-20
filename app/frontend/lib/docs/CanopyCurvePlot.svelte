<script lang="ts">
  // A crop's percent cover curve by day since emergence, for its card on the About page: gridlines at
  // 50% and 80% (where crop ET reaches reference ET) and a tick every 30 days. Pointing at it shows the
  // day and cover, and for a curve that runs in degree days (degreeDaysPerDay, the typical season's
  // rate the curve was converted at) the °C days that cover takes.
  let {
    covers,
    label,
    degreeDaysPerDay = null,
  }: { covers: number[]; label: string; degreeDaysPerDay?: number | null } = $props()

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

  let svg: SVGSVGElement | undefined = $state()
  let day: number | null = $state(null)

  function point(event: PointerEvent) {
    if (!svg) return
    const box = svg.getBoundingClientRect()
    const along = ((event.clientX - box.left) / box.width) * width
    const nearest = Math.round(((along - left) / (width - left - right)) * days)
    day = nearest >= 0 && nearest <= days ? nearest : null
  }

  // The tooltip's left edge as a share of the plot's width, kept inside it
  const tipLeft = $derived(day === null ? 0 : (x(day) / width) * 100)
</script>

<div class="relative">
  <svg
    bind:this={svg}
    viewBox="0 0 {width} {height}"
    class="h-auto w-full touch-pan-y"
    role="img"
    aria-label={label}
    onpointermove={point}
    onpointerdown={point}
    onpointerleave={() => (day = null)}
  >
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
    {#each ticks as tick (tick)}
      <text x={x(tick)} y={height - 4} text-anchor="middle" class="fill-ink-muted text-[9px]">{tick}</text>
    {/each}
    <path d={path} fill="none" stroke="var(--color-chart-canopy)" stroke-width="2" stroke-linejoin="round" />
    {#if day !== null}
      <line x1={x(day)} x2={x(day)} y1={top} y2={height - bottom} class="stroke-ink-muted" stroke-width="0.75" />
      <circle cx={x(day)} cy={y(covers[day])} r="3" fill="var(--color-chart-canopy)" />
    {/if}
  </svg>
  {#if day !== null}
    <div
      class="pointer-events-none absolute top-0 z-10 rounded border border-line bg-surface-raised px-2 py-1 text-xs whitespace-nowrap shadow-sm"
      style:left="{tipLeft}%"
      style:transform="translateX({tipLeft > 60 ? '-105%' : '5%'})"
      aria-hidden="true"
    >
      <div class="font-medium">{covers[day].toFixed(0)}% cover</div>
      {#if degreeDaysPerDay}
        <div>{Math.round((day * degreeDaysPerDay) / 10) * 10} °C days after emergence</div>
        <div class="text-ink-muted">typically day {day}</div>
      {:else}
        <div>Day {day} after emergence</div>
      {/if}
    </div>
  {/if}
</div>
