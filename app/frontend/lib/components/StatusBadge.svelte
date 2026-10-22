<script lang="ts">
  import type { PlantingSummary } from '@/types/serializers'

  // A field's water status (PLAN.md §5.5), always with an icon and label, never color alone. The
  // icon size (map markers) shows the label only to screen readers and as a tooltip.
  let {
    status,
    size = 'md',
    title,
  }: { status: PlantingSummary['status']; size?: 'icon' | 'sm' | 'md'; title?: string } = $props()

  const styles = {
    full: { label: 'Full', icon: '●', class: 'bg-status-full text-white' },
    ok: { label: 'OK', icon: '✓', class: 'bg-status-ok text-white' },
    caution: { label: 'Caution', icon: '!', class: 'bg-status-caution text-on-caution' },
    irrigate: { label: 'Irrigate', icon: '▲', class: 'bg-status-irrigate text-white' },
  }
  const style = $derived(status ? styles[status] : null)
</script>

{#if style && size === 'icon'}
  <span
    class="inline-flex size-5 items-center justify-center rounded-full text-[0.65rem] leading-none font-bold
      ring-1 ring-white/80 {style.class}"
    title={title ?? style.label}
  >
    <span aria-hidden="true">{style.icon}</span><span class="sr-only">{title ?? style.label}</span>
  </span>
{:else if style}
  <span
    class="inline-flex items-center gap-1 rounded-full font-medium {style.class}
      {size === 'sm' ? 'px-2 py-0.5 text-xs' : 'px-3 py-1 text-sm'}"
    {title}
  >
    <span aria-hidden="true">{style.icon}</span>{style.label}
  </span>
{:else}
  <span class="inline-flex rounded-full border border-line px-2 py-0.5 text-xs text-ink-muted">No status</span>
{/if}
