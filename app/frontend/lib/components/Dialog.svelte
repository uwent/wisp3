<script lang="ts">
  import type { Snippet } from 'svelte'
  import { Dialog } from 'bits-ui'

  let {
    open = $bindable(false),
    title,
    description,
    children,
    wide = false,
  }: { open?: boolean; title: string; description?: string; children: Snippet; wide?: boolean } = $props()
</script>

<Dialog.Root bind:open>
  <Dialog.Portal>
    <Dialog.Overlay class="fixed inset-0 z-40 bg-black/40" />
    <!-- No scroll lock: hiding the page's scrollbar shifted and shook the page (PLAN.md G.1), so the
         page behind still scrolls, and the dialog scrolls on its own without dragging it -->
    <Dialog.Content
      preventScroll={false}
      class="fixed top-1/2 left-1/2 z-50 max-h-[90dvh] w-[calc(100%-2rem)] -translate-x-1/2 -translate-y-1/2 overflow-y-auto overscroll-contain
        rounded-lg border border-line bg-surface-raised p-6 shadow-xl {wide ? 'max-w-2xl' : 'max-w-lg'}"
    >
      <div class="mb-4 flex items-start justify-between gap-4">
        <div>
          <Dialog.Title class="text-lg font-medium">{title}</Dialog.Title>
          {#if description}<Dialog.Description class="text-sm text-ink-muted">{description}</Dialog.Description>{/if}
        </div>
        <Dialog.Close class="text-ink-muted hover:text-ink" aria-label="Close">✕</Dialog.Close>
      </div>
      {@render children()}
    </Dialog.Content>
  </Dialog.Portal>
</Dialog.Root>
