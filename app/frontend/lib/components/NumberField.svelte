<script lang="ts">
  import { untrack } from 'svelte'
  import { page } from '@inertiajs/svelte'

  import { parseNumber, type Quantity, units as unitsFor } from '@/lib/units'

  // A number input in the user's units (Q3). What's typed is shown as-is; a hidden input carries
  // the value converted to the stored unit, under `name`, for Inertia's <Form>.
  let {
    label,
    name,
    quantity,
    value = $bindable(null),
    error,
    hint,
    required = false,
    placeholder,
    unitLabel,
    scale = 1,
    hideLabel = false,
    id = `field-${name.replace(/[^a-z0-9]+/gi, '-')}`,
  }: {
    label: string
    name: string
    /** Omit for plain numbers (percents, degrees) */
    quantity?: Quantity
    /** The stored value */
    value?: number | null
    error?: string | string[]
    hint?: string
    required?: boolean
    placeholder?: string
    /** Shown after the box when there's no quantity, e.g. "%" */
    unitLabel?: string
    /** For plain numbers: shown = stored × scale (e.g. 100 to enter a fraction as a percent) */
    scale?: number
    /** Label for screen readers only (in table cells) */
    hideLabel?: boolean
    id?: string
  } = $props()

  const units = $derived(unitsFor(page.props.auth.user?.unit_system))
  const show = (stored: number | null) =>
    quantity ? units.input(quantity, stored) : stored === null ? '' : String(Number((stored * scale).toFixed(6)))

  let text = $state(untrack(() => show(value)))
  let localError = $state<string | null>(null)
  // The value this box last produced; any other value was set from outside (e.g. the map picker)
  let own = untrack(() => value)

  $effect(() => {
    if (value !== own) {
      own = value
      text = untrack(() => show(value))
      localError = null
    }
  })

  function update(input: string) {
    text = input
    const parsed = quantity ? units.parse(quantity, input) : parseNumber(input)
    localError = parsed.ok ? null : parsed.error
    if (parsed.ok) value = own = parsed.value === null || quantity ? parsed.value : parsed.value / scale
  }

  const message = $derived(localError ?? (Array.isArray(error) ? error[0] : error))
  const suffix = $derived(quantity ? units.label(quantity) : unitLabel)
</script>

<div class={hideLabel ? '' : 'space-y-1'}>
  <label for={id} class={hideLabel ? 'sr-only' : 'block text-sm font-medium'}>{label}</label>
  <div class="flex items-center gap-2">
    <input
      {id}
      type="text"
      inputmode="decimal"
      class="block w-full min-w-0 rounded-md shadow-sm focus:border-brand-500 focus:ring-brand-500 sm:text-sm
        {message ? 'border-status-irrigate' : ''}"
      value={text}
      oninput={(event) => update(event.currentTarget.value)}
      aria-invalid={message ? 'true' : undefined}
      aria-describedby={message ? `${id}-error` : hint ? `${id}-hint` : undefined}
      {required}
      {placeholder}
    />
    {#if suffix && !hideLabel}<span class="shrink-0 text-sm text-ink-muted">{suffix}</span>{/if}
  </div>
  <input type="hidden" {name} value={value ?? ''} />
  {#if message}
    <p id="{id}-error" class="text-xs text-status-irrigate sm:text-sm">{message}</p>
  {:else if hint}
    <p id="{id}-hint" class="text-sm text-ink-muted">{hint}</p>
  {/if}
</div>
