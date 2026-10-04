<script lang="ts">
  // An (i) button with an explanation: shown while a mouse hovers it, and toggled by click or tap
  // (and Enter or Space), so it works on phones and from the keyboard. A click pins a hovered tip; a click on a pinned one, Escape,
  // or leaving closes it.
  let { text, label = 'About this' }: { text: string; label?: string } = $props()

  const id = $props.id()
  let hovered = $state(false)
  let pinned = $state(false)
  const open = $derived(hovered || pinned)
</script>

<span class="relative inline-flex">
  <button
    type="button"
    class="inline-flex size-6 items-center justify-center rounded-full text-ink-muted hover:bg-surface hover:text-ink focus-visible:outline-2 focus-visible:outline-brand-600"
    aria-label={label}
    aria-expanded={open}
    aria-describedby={open ? id : undefined}
    onclick={() => (pinned ? (pinned = hovered = false) : (pinned = true))}
    onpointerenter={(event) => event.pointerType === 'mouse' && (hovered = true)}
    onpointerleave={(event) => event.pointerType === 'mouse' && (hovered = false)}
    onblur={() => (pinned = false)}
    onkeydown={(event) => event.key === 'Escape' && (pinned = hovered = false)}
  >
    <svg viewBox="0 0 24 24" class="size-4" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true">
      <circle cx="12" cy="12" r="9" />
      <path d="M12 11v5M12 8h.01" />
    </svg>
  </button>
  {#if open}
    <span
      role="tooltip"
      {id}
      class="absolute top-full right-0 z-20 mt-1 w-72 max-w-[calc(100vw-2rem)] rounded-md border border-line bg-surface-raised p-3 text-xs leading-relaxed font-normal text-ink shadow-lg"
    >
      {text}
    </span>
  {/if}
</span>
