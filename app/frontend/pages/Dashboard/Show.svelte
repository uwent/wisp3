<script lang="ts">
  import { page } from '@inertiajs/svelte'

  const auth = $derived(page.props.auth)
</script>

<svelte:head><title>Dashboard · WISP</title></svelte:head>

<div class="flex flex-wrap items-end justify-between gap-2">
  <div>
    <h1 class="text-2xl font-semibold">Dashboard</h1>
    <p class="text-sm text-ink-muted">{auth.group?.name}</p>
  </div>
</div>

<section class="rounded-lg border border-dashed border-line bg-surface-raised px-6 py-12 text-center">
  <h2 class="text-lg font-medium">No farms yet</h2>
  <p class="mx-auto mt-2 max-w-md text-sm text-ink-muted">
    This is where each field's water status will appear: today's allowable depletion, the forecast, and when it's
    likely to need irrigation. Farm, pivot and field setup is coming next.
  </p>
  <div class="mt-6 flex justify-center gap-3 text-xs" aria-label="Status colors">
    <span class="rounded-full bg-status-full px-3 py-1 text-white">Full</span>
    <span class="rounded-full bg-status-ok px-3 py-1 text-white">OK</span>
    <span class="rounded-full bg-status-caution px-3 py-1 text-ink">Caution</span>
    <span class="rounded-full bg-status-irrigate px-3 py-1 text-white">Irrigate</span>
  </div>
</section>
