<script lang="ts">
  import type { Units } from '@/lib/units'

  import { type Legend, NONE_COLOR } from './overlays'

  // An overlay's legend, with its "none" class: the light gray the map shows where it has nothing
  let { legend, none, units }: { legend: Legend; none: string; units: Units } = $props()
</script>

<div class="space-y-1.5">
  {#if legend.kind === 'ramp'}
    <div>
      <div class="h-2.5 rounded-sm" style:background="linear-gradient(to right, {legend.colors.join(', ')})"></div>
      <div class="mt-0.5 flex justify-between text-xs text-ink-muted">
        <span>{legend.start}</span><span>{legend.end}</span>
      </div>
    </div>
  {:else if legend.kind === 'depths'}
    <div>
      <ul class="grid grid-cols-5 gap-x-1 gap-y-1 text-xs">
        {#each legend.items as item (item.inches)}
          <li class="flex flex-col items-center">
            <span class="h-2.5 w-full rounded-sm" style:background={item.color}></span>
            <span class="text-ink-muted tabular-nums">{units.format('depth', item.inches, { unit: false })}</span>
          </li>
        {/each}
      </ul>
      <p class="text-xs text-ink-muted">At least this much, in {units.label('depth')}</p>
    </div>
  {:else}
    <ul class="space-y-0.5 text-xs">
      {#each legend.items as item (item.label)}
        <li class="flex items-center gap-1.5">
          <span class="size-3 rounded-sm border border-line" style:background={item.color}></span>{item.label}
        </li>
      {/each}
    </ul>
  {/if}
  <p class="flex items-center gap-1.5 text-xs">
    <span class="size-3 rounded-sm border border-line" style:background={NONE_COLOR}></span>{none}
    <span class="text-ink-muted">(light gray)</span>
  </p>
</div>
