<script lang="ts">
  import type { PlantingSummary } from '@/types/serializers'

  // A field's water status (PLAN.md §5.5), always with an icon and label, never color alone
  let { status, size = 'md' }: { status: PlantingSummary['status']; size?: 'sm' | 'md' } = $props()

  const styles = {
    full: { label: 'Full', icon: '●', class: 'bg-status-full text-white' },
    ok: { label: 'OK', icon: '✓', class: 'bg-status-ok text-white' },
    caution: { label: 'Caution', icon: '!', class: 'bg-status-caution text-ink' },
    irrigate: { label: 'Irrigate', icon: '▲', class: 'bg-status-irrigate text-white' },
  }
  const style = $derived(status ? styles[status] : null)
</script>

{#if style}
  <span
    class="inline-flex items-center gap-1 rounded-full font-medium {style.class}
      {size === 'sm' ? 'px-2 py-0.5 text-xs' : 'px-3 py-1 text-sm'}"
  >
    <span aria-hidden="true">{style.icon}</span>{style.label}
  </span>
{:else}
  <span class="inline-flex rounded-full border border-line px-2 py-0.5 text-xs text-ink-muted">No status</span>
{/if}
