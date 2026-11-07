<script lang="ts">
  import { page } from '@inertiajs/svelte'
  import { slide } from 'svelte/transition'

  // How long a notice stays before it dismisses itself. Alerts stay until
  // dismissed: they report something that went wrong, so they shouldn't vanish.
  const NOTICE_MS = 6000

  type Kind = 'alert' | 'notice'

  // Dismissed messages stay hidden until the server sends a new flash. A new
  // flash reuses a message's box, changing its text; its generation restarts
  // the countdown, even for the same text
  let dismissed = $state<Kind[]>([])
  let pinned = $state<Kind[]>([])
  let generation = $state(0)
  let lastFlash: unknown = page.flash

  $effect(() => {
    if (page.flash !== lastFlash) {
      lastFlash = page.flash
      dismissed = []
      pinned = []
      generation += 1
    }
  })

  // The countdown is the bar's CSS animation, so pausing it (hover, focus, a
  // hidden tab) pauses the timer too, and its end dismisses the message
  let tabHidden = $state(typeof document !== 'undefined' && document.hidden)

  const messages = $derived(
    [
      page.flash?.alert && { kind: 'alert' as const, text: page.flash.alert },
      page.flash?.notice && { kind: 'notice' as const, text: page.flash.notice },
    ].filter((m) => !!m && !dismissed.includes(m.kind)) as { kind: Kind; text: string }[],
  )

  const dismiss = (kind: Kind) => (dismissed = [...dismissed, kind])
  const pin = (kind: Kind) => {
    if (!pinned.includes(kind)) pinned = [...pinned, kind]
  }
</script>

<svelte:document onvisibilitychange={() => (tabHidden = document.hidden)} />

{#each messages as message (message.kind)}
  {@const timed = message.kind === 'notice' && !pinned.includes(message.kind)}
  <!-- It slides away only when dismissed (by its timer or button); a page whose
       flash has no message of this kind just drops it -->
  <!-- Clicking the message keeps it (stops the timer); the keyboard equivalent
       is focusing its dismiss button, which pauses the timer while focused -->
  <div
    role={message.kind === 'alert' ? 'alert' : 'status'}
    out:slide={{ duration: dismissed.includes(message.kind) ? 150 : 0 }}
    class="group relative flex items-start justify-between gap-4 overflow-hidden rounded-md border px-4 py-3 text-sm
      {message.kind === 'alert'
      ? 'border-status-irrigate/40 bg-status-irrigate/10'
      : 'border-status-ok/40 bg-status-ok/10'}"
    onclick={() => pin(message.kind)}
  >
    <p>{message.text}</p>
    <button
      type="button"
      class="text-ink-muted hover:text-ink"
      aria-label="Dismiss message"
      onclick={(event) => {
        event.stopPropagation()
        dismiss(message.kind)
      }}>✕</button
    >
    {#key generation}
      {#if timed}
        <!-- The duration is !important to beat application.css's reduced-motion rule,
           which ends animations at once: this one is the timer, and a slow 2px bar
           isn't the motion that setting guards against -->
        <div
          aria-hidden="true"
          class="countdown absolute inset-x-0 bottom-0 h-0.5 origin-left bg-status-ok group-focus-within:[animation-play-state:paused] group-hover:[animation-play-state:paused]"
          class:paused={tabHidden}
          style="animation-duration: {NOTICE_MS}ms !important"
          onanimationend={() => dismiss(message.kind)}
        ></div>
      {/if}
    {/key}
  </div>
{/each}

<style>
  .countdown {
    animation-name: countdown;
    animation-timing-function: linear;
    animation-fill-mode: forwards;
  }

  .countdown.paused {
    animation-play-state: paused;
  }

  @keyframes countdown {
    from {
      transform: scaleX(1);
    }
    to {
      transform: scaleX(0);
    }
  }
</style>
