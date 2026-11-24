<script lang="ts">
  // Under a soil menu: how the soil chosen fits the soil survey's shares (soilFit), and "Use {main
  // soil}" when it isn't the main one (FieldSoilInput, quick setup's fields)
  let {
    fit,
    onuse,
  }: {
    fit: { note: string; absent: boolean; main: { id: number; name: string } | null | undefined }
    onuse: (id: number) => void
  } = $props()
</script>

<p class={fit.absent ? 'text-status-caution-ink' : 'text-ink-muted'}>{fit.note}</p>
{#if fit.main}<button
    type="button"
    class="mt-0.5 block text-brand-600 underline underline-offset-2"
    onclick={() => onuse(fit.main!.id)}
  >
    Use {fit.main.name}
  </button>{/if}
