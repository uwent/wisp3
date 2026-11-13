<script lang="ts">
  import { type Boundary, isPoint, type PivotShape } from '@/lib/geo'
  import SelectField from '@/lib/components/SelectField.svelte'
  import SoilSurvey from '@/lib/components/SoilSurvey.svelte'
  import { soilFit, soilOptionsByShare } from '@/lib/soils'
  import type { SoilType } from '@/types/serializers'

  // A field's soil (PLAN.md Phase 8 G.14 part 7): the soil saved beside the menu (labeled with each soil's
  // share once the soil survey answers) and the survey itself, read under the field's shape or else
  // its system. The same in the field dialog and on the shape page.
  let {
    name,
    value = $bindable(),
    soilTypes,
    saved,
    boundary = null,
    system = null,
    suggest = false,
    error,
    onchange,
  }: {
    name: string
    /** The soil type's id in the menu */
    value: string
    soilTypes: SoilType[]
    /** The field's saved soil type id; left out for a new field */
    saved?: number | null
    /** The field's shape, surveyed in place of its system */
    boundary?: Boundary | null
    /** The field's system and its name, surveyed when there's no shape */
    system?: (PivotShape & { name: string }) | null
    /** Take the survey's suggestion until a soil is picked (a new field) */
    suggest?: boolean
    error?: string | string[]
    /** Called when the user changes the soil (not the survey's suggestion) */
    onchange?: () => void
  } = $props()

  let chosen = $state(false)
  let fromSurvey = $state(false)
  let shares = $state<Map<string, number> | null>(null)

  const soil = $derived(soilTypes.find((s) => String(s.id) === value))
  const savedSoil = $derived(soilTypes.find((s) => s.id === saved))
  const surveyed = $derived(boundary !== null || system !== null)
  // "in the field", "under North 160", "around Lane 3"; and the menu's "5% of …"
  const near = $derived(
    boundary ? 'in the field' : system ? `${isPoint(system.kind) ? 'around' : 'under'} ${system.name}` : '',
  )
  const fit = $derived(soil && shares && surveyed ? soilFit(soil, shares, soilTypes, near) : null)
  const options = $derived(
    shares && surveyed
      ? soilOptionsByShare(soilTypes, shares, boundary ? 'the field' : system!.name)
      : soilTypes.map((s) => ({ value: String(s.id), label: s.name })),
  )

  function survey(suggested: SoilType | null, found: Map<string, number>) {
    shares = found
    if (!suggest || chosen || !suggested) return
    value = String(suggested.id)
    fromSurvey = true
  }

  function pick(id: string) {
    value = id
    chosen = true
    fromSurvey = false
    onchange?.()
  }
</script>

<div class="space-y-2">
  {#if saved === undefined}
    {@render menu('Soil')}
  {:else}
    <!-- The soil saved beside the menu, its value level with the menu's; stacked where there's no room (a 320 px phone) -->
    <div class="@container">
      <div class="grid gap-x-4 gap-y-2 @xs:grid-cols-[auto_minmax(0,1fr)]">
        <div class="space-y-1">
          <p class="text-sm font-medium">Current soil</p>
          <p class="py-2 text-sm">{savedSoil?.name ?? 'None'}</p>
        </div>
        {@render menu('New soil')}
      </div>
    </div>
  {/if}
  {#snippet menu(label: string)}
    <SelectField
      {label}
      {name}
      bind:value
      onchange={() => {
        chosen = true
        fromSurvey = false
        onchange?.()
      }}
      {options}
      {error}
      hint={fromSurvey ? 'From the soil survey' : undefined}
      note={fit ? soilNote : undefined}
    />
  {/snippet}
  {#snippet soilNote()}
    <p class={fit!.absent ? 'text-status-caution-ink' : 'text-ink-muted'}>{fit!.note}</p>
    {#if fit!.main}<button
        type="button"
        class="mt-0.5 block text-brand-600 underline underline-offset-2"
        onclick={() => pick(String(fit!.main!.id))}>Use {fit!.main.name}</button
      >{/if}
  {/snippet}
  {#if boundary}
    <SoilSurvey {boundary} {soilTypes} onsuggest={survey} />
  {:else if system}
    <SoilSurvey shape={system} {soilTypes} onsuggest={survey} />
  {/if}
</div>
