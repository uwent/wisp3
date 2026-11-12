<script lang="ts">
  import StatusBadge from '@/lib/components/StatusBadge.svelte'

  import { type Badge, packRows } from './pivots'

  // Badges packed in rows of about √n (G.14: three make a triangle, four a square), on a dark
  // backing. Each carries its hover label's lines (data-hover, read by OverviewMap under the
  // pointer) and names itself to screen readers.
  let { badges, selected = false }: { badges: Badge[]; selected?: boolean } = $props()

  const rows = $derived(packRows(badges))
</script>

<span
  class="flex flex-col items-center gap-0.5 bg-black/50 p-0.5 {rows.length > 1 ? 'rounded-xl' : 'rounded-full'}
    {selected ? 'ring-2 ring-white' : ''}"
>
  {#each rows as row, index (index)}
    <span class="flex gap-0.5">
      {#each row as badge (badge.key)}
        <span class="flex" data-hover={badge.lines.join('\n')}>
          {#if badge.status}
            <StatusBadge status={badge.status} size="icon" title={badge.lines.join(', ')} tooltip={false} />
          {:else}
            <span class="inline-flex size-5 rounded-full border-2 border-white/80 bg-gray-400/70"
              ><span class="sr-only">{badge.lines.join(', ')}</span></span
            >
          {/if}
        </span>
      {/each}
    </span>
  {/each}
</span>
