<script lang="ts">
  import { Link, page, router } from '@inertiajs/svelte'

  import Dialog from '@/lib/components/Dialog.svelte'
  import { mayDelete } from '@/lib/permissions'
  import { nextSeason } from '@/lib/plantings'
  import PlantingForm from '@/lib/setup/PlantingForm.svelte'
  import { changesMessage } from '@/lib/unsaved.svelte'
  import { planting as plantingRoute, plantings } from '@/routes'
  import type { Field, GenericCurve, Plant, Planting, SoilType } from '@/types/serializers'

  // Adding or editing a planting on a field (Setup, the field page): the form, and for an existing
  // planting, "Add the next planting" (a season starting the day after it ends, the same size) and
  // delete. Open it with open(field, planting?). systemFields: the fields on a field's irrigation
  // system, with their plantings, where the page has them, for "Also plant this on" (Phase 9 §7).
  let {
    year,
    plants,
    soilTypes,
    genericCurves,
    systemFields,
  }: {
    year: number
    plants: Plant[]
    soilTypes: SoilType[]
    genericCurves: GenericCurve[]
    systemFields?: (field: Field) => Field[]
  } = $props()

  let isOpen = $state(false)
  let field = $state<Field | null>(null)
  let planting = $state<Planting | undefined>()
  let template = $state<Partial<Planting> | undefined>()
  // Remounts the form when it switches to another planting
  let key = $state(0)

  export function open(target: Field, existing?: Planting) {
    field = target
    planting = existing
    template = undefined
    key++
    isOpen = true
  }

  // The form is swapped for a new one: ask first, as leaving would
  function addNext() {
    if (!planting || !leave()) return
    const { partial, plot_length_ft, plot_width_ft, area_acres } = planting
    template = {
      ...nextSeason(planting),
      partial,
      plot_length_ft,
      plot_width_ft,
      area_acres: partial ? area_acres : null,
    }
    planting = undefined
    key++
  }

  const close = () => (isOpen = false)

  // Leaving for the planting's page drops what's typed: ask first, listing it (G.13)
  let dialog: Dialog | undefined = $state()
  function leave() {
    const message = changesMessage(dialog?.changes() ?? [], 'this form')
    return message === null || confirm(message)
  }

  function destroy() {
    if (!planting) return
    if (!confirm(`Delete this ${planting.plant_name} planting and its canopy readings? This can't be undone.`)) return
    router.delete(plantings.destroy(planting.id).url, { preserveScroll: true })
    close()
  }

  const title = $derived(
    !field
      ? ''
      : planting
        ? `Edit ${planting.plant_name} on ${field.name}`
        : template
          ? `Add the next planting on ${field.name}`
          : `Add a ${year} planting to ${field.name}`,
  )
</script>

<Dialog bind:this={dialog} bind:open={isOpen} {title} wide guard>
  {#if field}
    {#if planting}
      <p class="-mt-2 mb-4 text-sm">
        <Link
          href={plantingRoute(planting.id)}
          class="text-brand-600 underline underline-offset-2"
          onBefore={leave}
          onSuccess={close}>View this planting</Link
        >
      </p>
    {/if}
    {#key key}
      <PlantingForm
        {planting}
        {field}
        year={template?.season_start ? Number(template.season_start.slice(0, 4)) : year}
        {plants}
        {soilTypes}
        {genericCurves}
        {template}
        systemFields={systemFields?.(field)}
        ondone={close}
        ondelete={planting && mayDelete(planting, page.props.auth) ? destroy : undefined}
      />
    {/key}
    {#if planting}
      <p class="mt-4 text-sm">
        <button type="button" class="text-brand-600 hover:underline" onclick={addNext}>Add the next planting</button>
      </p>
    {/if}
  {/if}
</Dialog>
