<script lang="ts">
  // AD over recent days, with the irrigate line (AD = 0) and field capacity for scale
  let {
    values,
    max,
    min,
    label,
    class: className = '',
  }: { values: number[]; max: number; min: number; label: string; class?: string } = $props()

  const width = 120
  const height = 32
  const y = (value: number) => height - 2 - ((value - min) / (max - min || 1)) * (height - 4)
  const x = (i: number) => (values.length < 2 ? width : (i / (values.length - 1)) * width)
  const path = $derived(values.map((value, i) => `${i ? 'L' : 'M'}${x(i).toFixed(1)},${y(value).toFixed(1)}`).join(''))
</script>

<svg viewBox="0 0 {width} {height}" class="h-8 w-full {className}" role="img" aria-label={label} preserveAspectRatio="none">
  <line x1="0" x2={width} y1={y(0)} y2={y(0)} class="stroke-status-irrigate" stroke-width="1" vector-effect="non-scaling-stroke" />
  <line x1="0" x2={width} y1={y(max)} y2={y(max)} class="stroke-line" stroke-width="1" stroke-dasharray="3 3" vector-effect="non-scaling-stroke" />
  {#if values.length}
    <path d={path} fill="none" class="stroke-chart-ad" stroke-width="2" vector-effect="non-scaling-stroke" />
  {/if}
</svg>
