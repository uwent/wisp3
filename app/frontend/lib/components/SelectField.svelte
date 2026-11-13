<script lang="ts">
  import type { Snippet } from 'svelte'
  import type { HTMLSelectAttributes } from 'svelte/elements'

  let {
    label,
    name,
    options,
    value = $bindable(),
    error,
    hint,
    note,
    id = `field-${(name ?? label).replace(/[^a-z0-9]+/gi, '-')}`,
    ...rest
  }: HTMLSelectAttributes & {
    label: string
    options: { value: string | number; label: string }[]
    error?: string | string[]
    hint?: string
    /** In place of the hint, for one that needs markup (a warning with a button) */
    note?: Snippet
  } = $props()

  const message = $derived(Array.isArray(error) ? error[0] : error)
</script>

<div class="space-y-1">
  <label for={id} class="block text-sm font-medium">{label}</label>
  <select
    {id}
    {name}
    bind:value
    class="block w-full rounded-md shadow-sm focus:border-brand-500 focus:ring-brand-500 disabled:cursor-not-allowed disabled:bg-surface disabled:text-ink-muted sm:text-sm
      {message ? 'border-status-irrigate' : ''}"
    aria-invalid={message ? 'true' : undefined}
    aria-describedby={message || hint || note ? `${id}-note` : undefined}
    {...rest}
  >
    {#each options as option (option.value)}
      <option value={option.value}>{option.label}</option>
    {/each}
  </select>
  {#if message}
    <p id="{id}-note" class="text-sm text-status-irrigate-ink">{message}</p>
  {:else if note}
    <div id="{id}-note" class="text-sm">{@render note()}</div>
  {:else if hint}
    <p id="{id}-note" class="text-sm text-ink-muted">{hint}</p>
  {/if}
</div>
