<script lang="ts">
  import { page } from '@inertiajs/svelte'

  // Dismissed messages stay hidden until the server sends a new flash
  let dismissed = $state(false)
  let lastFlash: unknown = null

  $effect(() => {
    if (page.flash !== lastFlash) {
      lastFlash = page.flash
      dismissed = false
    }
  })

  const messages = $derived(
    dismissed
      ? []
      : [
          page.flash?.alert && { kind: 'alert' as const, text: page.flash.alert },
          page.flash?.notice && { kind: 'notice' as const, text: page.flash.notice },
        ].filter((m) => !!m),
  )
</script>

{#each messages as message (message.kind)}
  <div
    role={message.kind === 'alert' ? 'alert' : 'status'}
    class="flex items-start justify-between gap-4 rounded-md border px-4 py-3 text-sm
      {message.kind === 'alert'
      ? 'border-status-irrigate/40 bg-status-irrigate/10'
      : 'border-status-ok/40 bg-status-ok/10'}"
  >
    <p>{message.text}</p>
    <button type="button" class="text-ink-muted hover:text-ink" aria-label="Dismiss" onclick={() => (dismissed = true)}
      >✕</button
    >
  </div>
{/each}
