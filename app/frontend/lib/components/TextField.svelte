<script lang="ts">
  import type { HTMLInputAttributes } from 'svelte/elements'

  let {
    label,
    name,
    error,
    hint,
    value = $bindable(),
    class: className = '',
    id = `field-${name.replace(/[^a-z0-9]+/gi, '-')}`,
    ...rest
  }: HTMLInputAttributes & {
    label: string
    name: string
    error?: string | string[]
    hint?: string
  } = $props()

  const message = $derived(Array.isArray(error) ? error[0] : error)
  // Only one of the error or the hint is rendered, so only reference that one
  const describedBy = $derived(message ? `${id}-error` : hint ? `${id}-hint` : undefined)
</script>

<div class="space-y-1">
  <label for={id} class="block text-sm font-medium">{label}</label>
  <input
    {id}
    {name}
    class="block w-full rounded-md shadow-sm focus:border-brand-500 focus:ring-brand-500 sm:text-sm
      {message ? 'border-status-irrigate' : ''} {className}"
    aria-invalid={message ? 'true' : undefined}
    aria-describedby={describedBy}
    bind:value
    {...rest}
  />
  {#if message}
    <p id="{id}-error" class="text-sm text-status-irrigate">{message}</p>
  {:else if hint}
    <p id="{id}-hint" class="text-sm text-ink-muted">{hint}</p>
  {/if}
</div>
