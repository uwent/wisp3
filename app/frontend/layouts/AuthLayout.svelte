<script lang="ts">
  import type { Snippet } from 'svelte'

  import FlashMessages from '@/lib/components/FlashMessages.svelte'
  import Logo from '@/lib/components/Logo.svelte'

  let { children }: { children: Snippet } = $props()
</script>

<div class="flex min-h-dvh flex-col items-center justify-center px-4 py-10">
  <div class="w-full max-w-md space-y-6">
    <div class="text-center">
      <Logo class="text-2xl" />
      <p class="mt-1 text-sm text-ink-muted">Wisconsin Irrigation Scheduling Program</p>
    </div>

    <FlashMessages />

    <div class="space-y-6 rounded-lg border border-line bg-surface-raised p-6 shadow-sm sm:p-8">
      {@render children()}
    </div>
  </div>
</div>
