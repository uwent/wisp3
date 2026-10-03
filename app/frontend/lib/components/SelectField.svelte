<script lang="ts">
  import type { HTMLSelectAttributes } from 'svelte/elements'

  let {
    label,
    name,
    options,
    value = $bindable(),
    error,
    hint,
    id = `field-${(name ?? label).replace(/[^a-z0-9]+/gi, '-')}`,
    ...rest
  }: HTMLSelectAttributes & {
    label: string
    options: { value: string | number; label: string }[]
    error?: string | string[]
    hint?: string
  } = $props()

  const message = $derived(Array.isArray(error) ? error[0] : error)
</script>

<div class="space-y-1">
  <label for={id} class="block text-sm font-medium">{label}</label>
  <select
    {id}
    {name}
    bind:value
    class="block w-full rounded-md shadow-sm focus:border-brand-500 focus:ring-brand-500 sm:text-sm
      {message ? 'border-status-irrigate' : ''}"
    aria-invalid={message ? 'true' : undefined}
    {...rest}
  >
    {#each options as option (option.value)}
      <option value={option.value}>{option.label}</option>
    {/each}
  </select>
  {#if message}
    <p class="text-sm text-status-irrigate">{message}</p>
  {:else if hint}
    <p class="text-sm text-ink-muted">{hint}</p>
  {/if}
</div>
