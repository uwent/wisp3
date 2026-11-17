<script lang="ts">
  import { type Snippet, untrack } from 'svelte'
  import { page } from '@inertiajs/svelte'

  import FieldLabel from '@/lib/components/FieldLabel.svelte'
  import type { FieldInfoKey } from '@/lib/fieldInfo'
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
    info,
    required = false,
    placeholder,
    unitLabel,
    scale = 1,
    hideLabel = false,
    optional = false,
    blankValue = null,
    submitBlankValue = false,
    after,
    id = `field-${(name ?? label).replace(/[^a-z0-9]+/gi, '-')}`,
  }: {
    label: string
    /** Omit for a box that isn't submitted (give it an id) */
    name?: string
    /** Omit for plain numbers (percents, degrees) */
    quantity?: Quantity
    /** The stored value */
    value?: number | null
    error?: string | string[]
    hint?: string
    /** An info tip by the label (lib/fieldInfo.ts) */
    info?: FieldInfoKey
    required?: boolean
    placeholder?: string
    /** Shown after the box when there's no quantity, e.g. "%" */
    unitLabel?: string
    /** For plain numbers: shown = stored × scale (e.g. 100 to enter a fraction as a percent) */
    scale?: number
    /** Label for screen readers only (in table cells) */
    hideLabel?: boolean
    /** Beside the box, after its unit (a button that fills it) */
    after?: Snippet
    /** Says "Optional" by the label */
    optional?: boolean
    /** The stored value a blank box stands for (a default), shown as its placeholder and in change lists */
    blankValue?: number | null
    /** Submit blankValue when the box is blank (a column that needs a value), not '' (NULL: the default) */
    submitBlankValue?: boolean
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

  // While what's typed can't be read, the form won't submit (the hidden input still holds the last
  // number read, which would otherwise be saved without a word)
  let box = $state<HTMLInputElement>()
  $effect(() => box?.setCustomValidity(localError ?? ''))

  function update(input: string) {
    text = input
    const parsed = quantity ? units.parse(quantity, input) : parseNumber(input)
    localError = parsed.ok ? null : parsed.error
    if (parsed.ok) value = own = parsed.value === null || quantity ? parsed.value : parsed.value / scale
  }

  // A default shown in the blank box: its placeholder, and what lib/formChanges.ts reads for blank
  const blankText = $derived(blankValue === null ? undefined : show(blankValue))
  const submitted = $derived(value ?? (submitBlankValue ? blankValue : null) ?? '')
  const message = $derived(localError ?? (Array.isArray(error) ? error[0] : error))
  // Required and still empty: marked until it has a value (G.13 part 3)
  const missing = $derived(required && !text.trim())
  const suffix = $derived(quantity ? units.label(quantity) : unitLabel)
</script>

<div class={hideLabel ? '' : 'space-y-1'}>
  <FieldLabel {label} {info} {missing} {optional} for={id} hidden={hideLabel} />
  <div class="flex items-center gap-2">
    <input
      bind:this={box}
      {id}
      type="text"
      inputmode="decimal"
      class="block w-full min-w-0 rounded-md shadow-sm focus:border-brand-500 focus:ring-brand-500 sm:text-sm
        {message ? 'border-status-irrigate' : missing ? 'border-l-4 border-l-brand-500' : ''}"
      value={text}
      data-unit={suffix}
      oninput={(event) => update(event.currentTarget.value)}
      aria-invalid={message ? 'true' : undefined}
      aria-describedby={message ? `${id}-error` : hint ? `${id}-hint` : undefined}
      data-blank={blankText}
      {required}
      placeholder={placeholder ?? blankText}
    />
    {#if suffix && !hideLabel}<span class="shrink-0 text-sm text-ink-muted">{suffix}</span>{/if}
    {@render after?.()}
  </div>
  {#if name}<input type="hidden" {name} value={submitted} />{/if}
  {#if message}
    <p id="{id}-error" class="text-xs text-status-irrigate-ink sm:text-sm">{message}</p>
  {:else if hint}
    <p id="{id}-hint" class="text-sm text-ink-muted">{hint}</p>
  {/if}
</div>
