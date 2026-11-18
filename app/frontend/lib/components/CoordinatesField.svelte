<script lang="ts">
  import { untrack } from 'svelte'

  import FieldLabel from '@/lib/components/FieldLabel.svelte'
  import { formatCoordinates, outsideUs, parseCoordinates } from '@/lib/coordinates'
  import type { FieldInfoKey } from '@/lib/fieldInfo'

  // A location's latitude and longitude in one box (lib/coordinates.ts reads what's pasted or typed:
  // Google Maps, a spreadsheet's two cells, degrees, minutes and seconds, a Maps link). What's typed
  // is shown as it is until the box loses focus, then written the one way; hidden inputs carry the
  // two numbers under `${prefix}[latitude]` and `${prefix}[longitude]`, for Inertia's <Form>.
  let {
    prefix,
    latitude = $bindable(null),
    longitude = $bindable(null),
    label = 'Coordinates',
    error,
    info,
    required = false,
    id = `field-${prefix.replace(/[^a-z0-9]+/gi, '-')}-coordinates`,
  }: {
    prefix: string
    latitude?: number | null
    longitude?: number | null
    label?: string
    error?: string | string[]
    /** An info tip by the label (lib/fieldInfo.ts) */
    info?: FieldInfoKey
    required?: boolean
    id?: string
  } = $props()

  const show = (lat: number | null, lng: number | null) =>
    lat === null || lng === null ? '' : formatCoordinates({ latitude: lat, longitude: lng })

  let text = $state(untrack(() => show(latitude, longitude)))
  let localError = $state<string | null>(null)
  let swapped = $state(false)
  // The location this box last produced; any other was set from outside (the map)
  let own = untrack(() => [latitude, longitude])

  $effect(() => {
    if (latitude !== own[0] || longitude !== own[1]) {
      own = [latitude, longitude]
      text = untrack(() => show(latitude, longitude))
      localError = null
      swapped = false
    }
  })

  // While what's typed can't be read, the form won't submit (the hidden inputs still hold the last
  // location read, which would otherwise be saved without a word)
  let box = $state<HTMLInputElement>()
  $effect(() => box?.setCustomValidity(localError ?? ''))

  function update(input: string) {
    text = input
    const parsed = parseCoordinates(input)
    localError = parsed.ok ? null : parsed.error
    if (!parsed.ok) return
    swapped = Boolean(parsed.swapped)
    latitude = parsed.value?.latitude ?? null
    longitude = parsed.value?.longitude ?? null
    own = [latitude, longitude]
  }

  // Once read, written the one way (a pasted 44°07'24"N becomes 44.123333)
  function tidy() {
    if (!localError) text = show(latitude, longitude)
  }

  const serverError = $derived(Array.isArray(error) ? error[0] : error)
  const message = $derived(localError ?? serverError)
  const warning = $derived(latitude === null || longitude === null ? null : outsideUs({ latitude, longitude }))
  const note = $derived(
    warning ?? (swapped ? 'Read as longitude, then latitude: the first number is the longitude.' : null),
  )
  const missing = $derived(required && !text.trim())
</script>

<div class="space-y-1">
  <FieldLabel {label} {info} {missing} for={id} />
  <input
    bind:this={box}
    {id}
    type="text"
    autocomplete="off"
    spellcheck="false"
    class="block w-full min-w-0 rounded-md shadow-sm focus:border-brand-500 focus:ring-brand-500 sm:text-sm
      {message ? 'border-status-irrigate' : missing ? 'border-l-4 border-l-brand-500' : ''}"
    value={text}
    oninput={(event) => update(event.currentTarget.value)}
    onblur={tidy}
    aria-invalid={message ? 'true' : undefined}
    aria-describedby={message || note ? `${id}-note` : undefined}
    {required}
    placeholder="Latitude, longitude"
  />
  <input type="hidden" name="{prefix}[latitude]" value={latitude ?? ''} />
  <input type="hidden" name="{prefix}[longitude]" value={longitude ?? ''} />
  {#if message}
    <p id="{id}-note" class="text-xs text-status-irrigate-ink sm:text-sm">{message}</p>
  {:else if note}
    <p id="{id}-note" class={warning ? 'text-sm text-status-caution-ink' : 'text-sm text-ink-muted'}>{note}</p>
  {/if}
</div>
