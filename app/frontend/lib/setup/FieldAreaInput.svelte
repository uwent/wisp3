<script lang="ts">
  import { page } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import NumberField from '@/lib/components/NumberField.svelte'
  import { units as unitsFor } from '@/lib/units'

  // A field's area (PLAN.md Phase 8 G.14 part 7): the area saved beside the box, with a button to copy
  // the shape's into it, and the shape's area under them, how far apart said (in the caution color when
  // it's far). The same in the field dialog and on the shape page; nothing
  // fills the box by itself.
  let {
    name,
    value = $bindable(null),
    saved,
    drawn = null,
    error,
    onchange,
  }: {
    name: string
    /** The area in the box, in acres */
    value?: number | null
    /** The field's saved area (null: none); left out for a new field */
    saved?: number | null
    /** The shape's area in acres, or null without one */
    drawn?: number | null
    error?: string | string[]
    /** Called when the button changes the box */
    onchange?: () => void
  } = $props()

  const units = $derived(unitsFor(page.props.auth.user?.unit_system))
  const format = (acres: number) => units.format('area', acres, { digits: 2 })
  const rounded = $derived(drawn === null ? null : Math.round(drawn * 100) / 100)

  // How far the area is from the shape's (to the hundredth shown), and whether that's worth a warning:
  // more than half an acre and more than a tenth apart
  const apart = $derived.by(() => {
    if (rounded === null || value === null) return null
    const difference = Math.round(Math.abs(value - rounded) * 100) / 100
    return difference > 0 ? difference : null
  })
  const far = $derived(apart !== null && apart > 0.5 && apart > 0.1 * Math.max(value!, rounded!))
</script>

<div class="space-y-2 text-sm">
  {#if saved === undefined}
    {@render box('Field area')}
  {:else}
    <!-- The area saved beside the box, its value level with the box's; stacked where there's no room (a 320 px phone) -->
    <div class="@container">
      <div class="grid gap-x-4 gap-y-2 @xs:grid-cols-[auto_minmax(0,1fr)]">
        <div class="space-y-1">
          <p class="font-medium">Current area</p>
          <p class="py-2">{saved === null ? 'None' : format(saved)}</p>
        </div>
        {@render box('New field area')}
      </div>
    </div>
  {/if}
  {#snippet box(label: string)}
    <div class="max-w-sm">
      <NumberField
        {label}
        {name}
        quantity="area"
        bind:value
        {error}
        after={rounded !== null && value !== rounded ? useDrawn : undefined}
      />
    </div>
  {/snippet}
  {#snippet useDrawn()}
    <Button
      type="button"
      variant="secondary"
      class="shrink-0"
      onclick={() => {
        value = rounded
        onchange?.()
      }}>Use {format(rounded!)}</Button
    >
  {/snippet}
  {#if rounded !== null}
    <p class={far ? 'text-status-caution-ink' : 'text-ink-muted'} role="status">
      Field as drawn: <span class="font-medium">{format(rounded)}</span>{apart === null
        ? '.'
        : `, ${format(apart)} ${value! > rounded ? 'less' : 'more'} than the area above.`}
      {#if far}Check that the shape covers the whole field, or that the area is right.{/if}
    </p>
  {/if}
</div>
