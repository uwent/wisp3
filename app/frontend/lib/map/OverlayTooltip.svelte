<script lang="ts">
  import type { Units } from '@/lib/units'

  import type { Probe, ProbeValue } from './mapOverlays.svelte'
  import { NONE_COLOR } from './overlays'

  // What the shown layers have under the pointer or a tap (MapOverlays.probe), next to it, kept
  // inside the map
  let { probe, units, width, height }: { probe: Probe; units: Units; width: number; height: number } = $props()

  const OFFSET = 14
  const left = $derived(probe.x > width - 260 ? probe.x - OFFSET : probe.x + OFFSET)
  const top = $derived(probe.y > height - 120 ? probe.y - OFFSET : probe.y + OFFSET)
  const shift = $derived(`${probe.x > width - 260 ? '-100%' : '0'} ${probe.y > height - 120 ? '-100%' : '0'}`)

  const depth = (inches: number) => units.format('depth', inches)
  function describe(value: ProbeValue, none: string): { text: string; color?: string; muted?: boolean } {
    if (value === 'loading') return { text: '…', muted: true }
    if (value === 'unavailable') return { text: 'Unavailable', muted: true }
    if (value === 'outside') return { text: 'No data outside the US', muted: true }
    if (value.kind === 'none') return { text: none, color: NONE_COLOR }
    if (value.kind === 'text') return { text: value.text, color: value.color }
    if (value.upTo === undefined) return { text: `About ${depth(value.inches)}` }
    if (value.upTo === null) return { text: `${depth(value.inches)} or more` }
    return { text: `${units.format('depth', value.inches, { unit: false })}–${depth(value.upTo)}` }
  }
</script>

<div
  class="pointer-events-none absolute z-30 max-w-64 rounded-md border border-line bg-surface-raised px-2.5 py-1.5 text-xs
    shadow-lg"
  style:left="{left}px"
  style:top="{top}px"
  style:translate={shift}
  role="status"
  aria-live="polite"
>
  <dl class="space-y-0.5">
    {#each probe.items as item (item.id)}
      {@const shown = describe(item.value, item.none)}
      <div>
        <dt class="text-ink-muted">{item.name}</dt>
        <dd class="flex items-center gap-1.5 font-medium {shown.muted ? 'font-normal text-ink-muted' : ''}">
          {#if shown.color}<span class="size-2.5 shrink-0 rounded-sm border border-line" style:background={shown.color}
            ></span>{/if}{shown.text}
        </dd>
      </div>
    {/each}
  </dl>
</div>
