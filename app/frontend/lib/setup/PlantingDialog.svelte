<script lang="ts">
  import { router } from '@inertiajs/svelte'

  import Dialog from '@/lib/components/Dialog.svelte'
  import { nextSeason } from '@/lib/plantings'
  import PlantingForm from '@/lib/setup/PlantingForm.svelte'
  import { plantings } from '@/routes'
  import type { Field, GenericCurve, Plant, Planting, SoilType } from '@/types/serializers'

  // Adding or editing a planting on a field (Setup, the field page): the form, and for an existing
  // planting, "Add the next planting" (a season starting the day after it ends, the same size) and
  // delete. Open it with open(field, planting?).
  let {
    year,
    plants,
    soilTypes,
    genericCurves,
  }: { year: number; plants: Plant[]; soilTypes: SoilType[]; genericCurves: GenericCurve[] } = $props()

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

  function addNext() {
    if (!planting) return
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

<Dialog bind:open={isOpen} {title} wide>
  {#if field}
    {#key key}
      <PlantingForm
        {planting}
        {field}
        year={template?.season_start ? Number(template.season_start.slice(0, 4)) : year}
        {plants}
        {soilTypes}
        {genericCurves}
        {template}
        ondone={close}
      />
    {/key}
    {#if planting}
      <div class="mt-4 flex flex-wrap items-center justify-between gap-3 text-sm">
        <button type="button" class="text-brand-600 hover:underline" onclick={addNext}> Add the next planting </button>
        <button type="button" class="text-status-irrigate-ink hover:underline" onclick={destroy}>
          Delete this planting
        </button>
      </div>
    {/if}
  {/if}
</Dialog>
