<script lang="ts">
  import { untrack } from 'svelte'
  import { Form, Link, page, router } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import NumberField from '@/lib/components/NumberField.svelte'
  import {
    applies,
    appliedLabel,
    common,
    count,
    farmRows,
    fieldHasEntry,
    inSeason,
    pivotHasEntry,
    plots,
    rainFields,
    wholeField,
    type DayFarm,
    type DayField,
    type DayPivot,
    type DayPlanting,
  } from '@/lib/dailyEntry'
  import { addDays, formatDate } from '@/lib/dates'
  import { KIND_NAMES, KIND_NOUNS } from '@/lib/geo'
  import { cropName, plotSize } from '@/lib/plantings'
  import { confirmUnsavedChanges, UNSAVED_MESSAGE } from '@/lib/unsaved.svelte'
  import { units as unitsFor } from '@/lib/units'
  import { dailyEntries, fields as fieldRoutes, newQuickSetup, plantings as plantingRoutes } from '@/routes'

  let { date, farms }: { date: string; farms: DayFarm[] } = $props()

  const units = $derived(unitsFor(page.props.auth.user?.unit_system))
  /** A system in a placeholder: "pivot", "traveler", "drip" */
  const short = (pivot: DayPivot) => KIND_NAMES[pivot.kind].toLowerCase()
  const today = new Date().toLocaleDateString('en-CA')

  // Typed values not yet saved: set by any input, cleared by a successful save
  let dirty = $state(false)
  confirmUnsavedChanges(() => dirty)

  /** Goes to another date, asking first if there are unsaved values; false if the user stayed */
  function go(to: string): boolean {
    if (dirty && !confirm(UNSAVED_MESSAGE)) return false
    dirty = false
    router.get(dailyEntries.show().url, { date: to })
    return true
  }

  const allPivots = $derived(farms.flatMap((farm) => farm.pivots))
  const allFields = $derived(allPivots.flatMap((pivot) => pivot.fields))

  // The values that other rows show or fill, from what's saved; reset when the page's data changes
  // (another date, or after a save)
  function saved(pivots: DayPivot[]) {
    const fields = pivots.flatMap((pivot) => pivot.fields)
    const hours = Object.fromEntries(pivots.map((p) => [p.id, p.irrigation !== null && p.irrigation.inches === null]))
    return {
      rain: Object.fromEntries(fields.map((f) => [f.id, f.entry?.rain_in ?? null])),
      fieldIrrigation: Object.fromEntries(fields.map((f) => [f.id, f.entry?.irrigation_in ?? null])),
      byHours: hours,
      pivotAmount: Object.fromEntries(
        pivots.map((p) => [p.id, hours[p.id] ? (p.irrigation?.run_hours ?? null) : (p.irrigation?.inches ?? null)]),
      ),
      applied: Object.fromEntries(pivots.map((p) => [p.id, p.irrigation?.field_ids ?? p.fields.map((f) => f.id)])),
    }
  }
  const initial = untrack(() => saved(allPivots))
  let rain = $state<Record<number, number | null>>(initial.rain)
  let fieldIrrigation = $state<Record<number, number | null>>(initial.fieldIrrigation)
  let pivotAmount = $state<Record<number, number | null>>(initial.pivotAmount)
  let applied = $state<Record<number, number[]>>(initial.applied)
  let byHours = $state<Record<number, boolean>>(initial.byHours)
  $effect(() => {
    const values = saved(allPivots)
    untrack(() => {
      ;({ rain, fieldIrrigation, pivotAmount, applied, byHours } = values)
    })
  })

  const canUseHours = (pivot: DayPivot) =>
    pivot.pump_capacity_gpm !== null && pivot.fields.every((f) => f.area_acres !== null)

  function switchHours(pivot: DayPivot, hours: boolean) {
    byHours[pivot.id] = hours
    pivotAmount[pivot.id] = hours ? (pivot.irrigation?.run_hours ?? null) : (pivot.irrigation?.inches ?? null)
  }

  const pivotReaches = (pivot: DayPivot, field: DayField) =>
    pivotAmount[pivot.id] != null && applies(applied[pivot.id] ?? null, field)

  /** A group's or pivot's rain: the fields' common value, or "varies" */
  const shared = (fields: DayField[]) => common(fields.map((f) => rain[f.id] ?? null))
  function fill(fields: DayField[], value: number | null) {
    for (const field of fields) rain[field.id] = value
    dirty = true
  }

  // Collapsed rows. A pivot group's or pivot's choice is remembered in this browser; the rest
  // (fields with no crop, plots, pivots with nothing in season) start closed unless something was
  // entered there that day
  const STORAGE_KEY = 'wisp.dailyEntry.collapsed'
  let collapsed = $state<Record<string, boolean>>(
    (() => {
      try {
        return JSON.parse(localStorage.getItem(STORAGE_KEY) ?? '{}')
      } catch {
        return {}
      }
    })(),
  )
  let opened = $state<Record<string, boolean>>({})
  function remember(key: string, isCollapsed: boolean) {
    collapsed[key] = isCollapsed
    try {
      const kept = Object.fromEntries(Object.entries(collapsed).filter(([, closed]) => closed))
      localStorage.setItem(STORAGE_KEY, JSON.stringify(kept))
    } catch {
      // Not remembered (private window, blocked storage): it still works on this page
    }
  }
  const isOpen = (key: string) => !collapsed[key]
  const shown = (key: string, byDefault: boolean) => opened[key] ?? byDefault

  const plotsOpenByDefault = (field: DayField) =>
    plots(field).some((p) => p.entry !== null || p.cover?.value != null || p.cover?.due)

  const anyCover = $derived(allFields.some((f) => f.plantings.some((p) => p.cover)))
  const coverKinds = $derived(new Set(allFields.flatMap((f) => f.plantings.flatMap((p) => p.cover?.kind ?? []))))
  const coverHeading = $derived(
    coverKinds.size > 1 ? 'Cover (% or LAI)' : coverKinds.has('lai') ? 'LAI' : 'Percent cover (%)',
  )
  const columns = $derived(anyCover ? 5 : 4)

  const e = (errors: Record<string, string | string[]>, key: string) => errors[key]

  // Indents for each level's name cell, with room for its expand toggle
  const indent = ['pl-8', 'pl-13', 'pl-18', 'pl-23']
  // Names stay in view while the table scrolls sideways (phones); each row sets its background
  const nameCell = 'sticky left-0 z-10 min-w-40 py-1.5 pr-2 text-left'
</script>

<svelte:head><title>Daily entry · WISP</title></svelte:head>

{#snippet toggle(label: string, expanded: boolean, onclick: () => void)}
  <button
    type="button"
    class="relative -ml-5 inline-flex size-5 items-center justify-center rounded text-ink-muted hover:bg-surface hover:text-ink"
    aria-expanded={expanded}
    aria-label={label}
    {onclick}
  >
    <span aria-hidden="true" class="inline-block transition-transform {expanded ? 'rotate-90' : ''}">▸</span>
  </button>
{/snippet}

{#snippet coverCell(planting: DayPlanting, label: string, errs: Record<string, string | string[]>)}
  {#if planting.cover}
    {@const cover = planting.cover}
    <NumberField
      hideLabel
      label="{cover.kind === 'lai' ? 'LAI' : 'Percent cover'} on {label}{cover.due ? ' (due)' : ''}"
      name="canopy[{planting.id}]"
      value={cover.value}
      error={e(errs, `canopy.${planting.id}`)}
    />
    {#if cover.value === null}
      <p class="mt-0.5 text-xs {cover.due ? 'font-medium text-status-caution-ink' : 'text-ink-muted'}">
        {#if cover.due}Due{cover.last_date
            ? ` · last ${formatDate(cover.last_date)}`
            : ''}{:else if cover.last_date}Last
          {formatDate(cover.last_date)}{/if}
      </p>
    {/if}
  {/if}
{/snippet}

<!-- A field's row, and its plots under it -->
{#snippet fieldRows(
  pivot: DayPivot,
  field: DayField,
  depth: number,
  hidden: boolean,
  errs: Record<string, string | string[]>,
)}
  {@const whole = wholeField(field)}
  {@const fieldPlots = plots(field)}
  {@const plotsKey = `plots-${field.id}`}
  {@const plotsOpen = shown(plotsKey, plotsOpenByDefault(field))}
  <tr class="align-top" {hidden}>
    <th scope="row" class="{nameCell} bg-surface-raised font-normal {indent[depth]}">
      <span class="flex items-start gap-1">
        {#if fieldPlots.length}
          {@render toggle(`Plots on ${field.name}`, plotsOpen, () => (opened[plotsKey] = !plotsOpen))}
        {/if}
        <span>
          <Link href={fieldRoutes.show(field.id)} class="hover:underline">{field.name}</Link>
          <span class="block text-xs text-ink-muted">
            {#if whole}{cropName(whole)}{fieldPlots.length ? ` + ${count(fieldPlots.length, 'plot')}` : ''}
            {:else if fieldPlots.length}{count(fieldPlots.length, 'plot')}
            {:else}No crop{/if}
          </span>
        </span>
      </span>
    </th>
    <td class="w-36 px-2 py-1.5">
      <NumberField
        hideLabel
        label="Rain on {field.name}"
        name="fields[{field.id}][rain_in]"
        quantity="depth"
        bind:value={rain[field.id]}
        placeholder={field.rain_model === null
          ? ''
          : `modeled ${units.format('depth', field.rain_model, { unit: false })}`}
        error={e(errs, `fields.${field.id}.rain_in`)}
      />
    </td>
    <td class="w-36 px-2 py-1.5">
      <NumberField
        hideLabel
        label="Irrigation on {field.name} (replaces the {KIND_NOUNS[pivot.kind]}'s)"
        name="fields[{field.id}][irrigation_in]"
        quantity="depth"
        bind:value={fieldIrrigation[field.id]}
        placeholder={pivotReaches(pivot, field) ? `${short(pivot)}'s` : ''}
        error={e(errs, `fields.${field.id}.irrigation_in`)}
      />
    </td>
    <td class="w-28 px-2 py-1.5">
      {#if whole || !inSeason(field)}
        <NumberField
          hideLabel
          label="Soil moisture reading on {field.name}"
          name="fields[{field.id}][soil_moisture_pct]"
          value={field.entry?.soil_moisture_pct ?? null}
          error={e(errs, `fields.${field.id}.soil_moisture_pct`)}
        />
      {:else}
        <!-- A field growing only plots: each plot's reading is on its own row -->
        <input
          type="hidden"
          name="fields[{field.id}][soil_moisture_pct]"
          value={field.entry?.soil_moisture_pct ?? ''}
        />
        <span class="block py-2 text-center text-ink-muted" aria-hidden="true">—</span>
      {/if}
    </td>
    {#if anyCover}
      <td class="w-28 px-2 py-1.5"
        >{#if whole}{@render coverCell(whole, field.name, errs)}{/if}</td
      >
    {/if}
  </tr>
  {#each fieldPlots as plot (plot.id)}
    {@const plotLabel = `${cropName(plot)}, ${plotSize(plot, units)}`}
    <tr class="align-top" hidden={hidden || !plotsOpen}>
      <th scope="row" class="{nameCell} bg-surface-raised font-normal {indent[depth + 1]}">
        <Link href={plantingRoutes.show(plot.id)} class="hover:underline">{cropName(plot)}</Link>
        <span class="block text-xs text-ink-muted">{plotSize(plot, units)}</span>
      </th>
      <td class="px-2 py-1.5 text-xs text-ink-muted"><span class="block py-2">field's</span></td>
      <td class="px-2 py-1.5">
        <NumberField
          hideLabel
          label="Irrigation on {plotLabel} on {field.name} (replaces the field's)"
          name="plantings[{plot.id}][irrigation_in]"
          quantity="depth"
          value={plot.entry?.irrigation_in ?? null}
          placeholder={fieldIrrigation[field.id] != null
            ? "field's"
            : pivotReaches(pivot, field)
              ? `${short(pivot)}'s`
              : ''}
          error={e(errs, `plantings.${plot.id}.irrigation_in`)}
        />
      </td>
      <td class="px-2 py-1.5">
        <NumberField
          hideLabel
          label="Soil moisture reading on {plotLabel} on {field.name}"
          name="plantings[{plot.id}][soil_moisture_pct]"
          value={plot.entry?.soil_moisture_pct ?? null}
          error={e(errs, `plantings.${plot.id}.soil_moisture_pct`)}
        />
      </td>
      {#if anyCover}
        <td class="px-2 py-1.5">{@render coverCell(plot, `${plotLabel} on ${field.name}`, errs)}</td>
      {/if}
    </tr>
  {/each}
{/snippet}

<!-- A pivot's row (its irrigation, and rain for all its fields), its fields, then those with no crop -->
{#snippet pivotRows(pivot: DayPivot, depth: number, hidden: boolean, errs: Record<string, string | string[]>)}
  {@const key = `pivot-${pivot.id}`}
  {@const open = isOpen(key)}
  {@const growing = pivot.fields.filter(inSeason)}
  {@const idle = pivot.fields.filter((f) => !inSeason(f))}
  {@const idleKey = `idle-${pivot.id}`}
  {@const idleOpen = shown(idleKey, idle.some(fieldHasEntry))}
  {@const appliedKey = `applied-${pivot.id}`}
  {@const appliedOpen = shown(appliedKey, false)}
  {@const rainShared = shared(growing)}
  <tr class="border-t border-line bg-surface align-top" {hidden}>
    <th scope="row" class="{nameCell} bg-surface {indent[depth]}">
      <span class="flex items-start gap-1">
        {@render toggle(`Fields on ${pivot.name}`, open, () => remember(key, open))}
        <span>
          <span class="font-medium">{pivot.name}</span>
          <span class="block text-xs font-normal text-ink-muted"
            >{`${pivot.kind_name} · ${count(pivot.fields.length, 'field')}`}</span
          >
        </span>
      </span>
    </th>
    <td class="px-2 py-1.5">
      {#if growing.length > 1}
        <NumberField
          hideLabel
          id="pivot-{pivot.id}-rain"
          label="Rain for all fields on {pivot.name}"
          quantity="depth"
          bind:value={() => rainShared.value, (value) => fill(growing, value)}
          placeholder={rainShared.varies ? 'varies' : 'all fields'}
        />
      {/if}
    </td>
    <td class="px-2 py-1.5" colspan={columns - 2}>
      <div class="flex flex-wrap items-start gap-x-3 gap-y-1">
        <div class="w-32">
          {#if byHours[pivot.id]}
            <NumberField
              hideLabel
              label="Run hours of {pivot.name}"
              name="pivots[{pivot.id}][run_hours]"
              unitLabel="h"
              bind:value={pivotAmount[pivot.id]}
              placeholder="hours"
              error={e(errs, `pivots.${pivot.id}.run_hours`)}
            />
            <input type="hidden" name="pivots[{pivot.id}][inches]" value="" />
          {:else}
            <NumberField
              hideLabel
              label="Irrigation by {pivot.name}"
              name="pivots[{pivot.id}][inches]"
              quantity="depth"
              bind:value={pivotAmount[pivot.id]}
              placeholder={short(pivot)}
              error={e(errs, `pivots.${pivot.id}.inches`)}
            />
            <input type="hidden" name="pivots[{pivot.id}][run_hours]" value="" />
          {/if}
        </div>
        {#if canUseHours(pivot)}
          <label class="flex items-center gap-1.5 py-2 text-xs">
            <input
              type="checkbox"
              class="rounded"
              checked={byHours[pivot.id]}
              onchange={(event) => switchHours(pivot, event.currentTarget.checked)}
            />
            Run hours
          </label>
        {/if}
        {#if pivot.fields.length > 1}
          <button
            type="button"
            class="py-2 text-xs text-brand-600 hover:underline"
            aria-expanded={appliedOpen}
            onclick={() => (opened[appliedKey] = !appliedOpen)}
          >
            Applied to: {appliedLabel(
              (applied[pivot.id] ?? []).length === pivot.fields.length ? null : (applied[pivot.id] ?? []),
              pivot.fields.length,
            )}
          </button>
        {/if}
      </div>
      {#if e(errs, `pivots.${pivot.id}.field_ids`)}<p class="text-xs text-status-irrigate-ink">
          {e(errs, `pivots.${pivot.id}.field_ids`)}
        </p>{/if}
    </td>
  </tr>
  {#if pivot.fields.length > 1}
    <!-- Always in the form (a hidden row still submits), so a saved choice of fields isn't lost -->
    <tr hidden={hidden || !appliedOpen}>
      <td colspan={columns} class="pb-2 {indent[depth + 1]}">
        <fieldset class="space-y-1">
          <legend class="text-xs font-medium">{pivot.name}'s irrigation applied to</legend>
          <input type="hidden" name="pivots[{pivot.id}][field_ids][]" value="" />
          <div class="flex flex-wrap gap-x-4 gap-y-1">
            {#each pivot.fields as field (field.id)}
              <label class="flex items-center gap-1.5 text-sm">
                <input
                  type="checkbox"
                  class="rounded"
                  name="pivots[{pivot.id}][field_ids][]"
                  value={field.id}
                  bind:group={applied[pivot.id]}
                />
                {field.name}
              </label>
            {/each}
          </div>
        </fieldset>
      </td>
    </tr>
  {/if}
  {#each growing as field (field.id)}
    {@render fieldRows(pivot, field, depth + 1, hidden || !open, errs)}
  {/each}
  {#if idle.length}
    <tr hidden={hidden || !open}>
      <td colspan={columns} class="py-1.5 {indent[depth + 1]}">
        <span class="flex items-center gap-1 text-xs text-ink-muted">
          {@render toggle(`Fields with no crop on ${pivot.name}`, idleOpen, () => (opened[idleKey] = !idleOpen))}
          {growing.length ? `${count(idle.length, 'field')} with no crop this season` : 'No crop this season'}
        </span>
      </td>
    </tr>
    {#each idle as field (field.id)}
      {@render fieldRows(pivot, field, depth + 1, hidden || !open || !idleOpen, errs)}
    {/each}
  {/if}
{/snippet}

<div class="flex flex-wrap items-end justify-between gap-3">
  <div>
    <h1 class="text-2xl font-semibold">Daily entry</h1>
    <p class="text-sm text-ink-muted">
      Rain, irrigation, soil moisture and percent cover for all your fields on one day.
    </p>
  </div>
  <div class="flex items-center gap-1">
    <Button variant="secondary" class="px-3" onclick={() => go(addDays(date, -1))} aria-label="Previous day">‹</Button>
    <input
      type="date"
      value={date}
      max={today}
      class="rounded-md text-sm"
      aria-label="Date"
      onchange={(event) => {
        if (!go(event.currentTarget.value)) event.currentTarget.value = date
      }}
    />
    <Button
      variant="secondary"
      class="px-3"
      onclick={() => go(addDays(date, 1))}
      disabled={date >= today}
      aria-label="Next day">›</Button
    >
  </div>
</div>

{#if allPivots.length === 0}
  <section
    class="rounded-lg border border-dashed border-line bg-surface-raised px-6 py-10 text-center text-sm text-ink-muted"
  >
    You haven't added an irrigation system yet. <Link
      href={newQuickSetup()}
      class="text-brand-600 underline underline-offset-2">Set up your first irrigation system</Link
    > to start entering rain and irrigation.
  </section>
{:else}
  {#key date}
    <Form
      action={dailyEntries.update()}
      class="space-y-6"
      options={{ preserveScroll: true }}
      oninput={() => (dirty = true)}
      onchange={() => (dirty = true)}
      onSuccess={() => (dirty = false)}
    >
      {#snippet children({ errors, processing, isDirty })}
        {@const errs = errors as Record<string, string | string[]>}
        <input type="hidden" name="date" value={date} />
        <div class="flex flex-wrap items-baseline justify-between gap-2">
          <h2 class="text-lg font-medium">{formatDate(date, { weekday: true, year: true })}</h2>
          <p class="text-xs text-ink-muted">
            Rain typed for an irrigation system or group fills in its fields; change any field before saving.
          </p>
        </div>

        {#each farms as farm (farm.id)}
          {@const rows = farmRows(farm)}
          {@const idleKey = `idle-farm-${farm.id}`}
          {@const idleOpen = shown(idleKey, rows.idle.some(pivotHasEntry))}
          {#if farm.pivots.length}
            <section class="space-y-2" aria-labelledby="farm-{farm.id}">
              <h3 id="farm-{farm.id}" class="font-medium text-ink-muted">{farm.name}</h3>
              <div class="relative overflow-x-auto rounded-lg border border-line bg-surface-raised">
                <table class="w-full min-w-xl text-sm">
                  <thead class="text-xs text-ink-muted">
                    <tr class="text-left">
                      <th class="sticky left-0 z-10 bg-surface-raised px-3 py-1.5 font-medium">System or field</th>
                      <th class="px-2 py-1.5 font-medium">Rain ({units.label('depth')})</th>
                      <th class="px-2 py-1.5 font-medium">Irrigation ({units.label('depth')})</th>
                      <th class="px-2 py-1.5 font-medium">Soil moisture (%)</th>
                      {#if anyCover}<th class="px-2 py-1.5 font-medium">{coverHeading}</th>{/if}
                    </tr>
                  </thead>
                  <tbody>
                    {#each rows.groups as group (group.id)}
                      {@const key = `group-${group.id}`}
                      {@const open = isOpen(key)}
                      {@const fields = rainFields(group.pivots)}
                      {@const rainShared = shared(fields)}
                      <tr class="border-t border-line bg-brand-50 align-top">
                        <th scope="row" class="{nameCell} bg-brand-50 {indent[0]}">
                          <span class="flex items-start gap-1">
                            {@render toggle(`Irrigation systems in ${group.name}`, open, () => remember(key, open))}
                            <span>
                              <span class="font-medium">{group.name}</span>
                              <span class="block text-xs font-normal text-ink-muted"
                                >{`Irrigation group · ${count(group.pivots.length, 'system')}`}</span
                              >
                            </span>
                          </span>
                        </th>
                        <td class="px-2 py-1.5">
                          <NumberField
                            hideLabel
                            id="group-{group.id}-rain"
                            label="Rain for all fields in {group.name}"
                            quantity="depth"
                            bind:value={() => rainShared.value, (value) => fill(fields, value)}
                            placeholder={rainShared.varies ? 'varies' : 'all fields'}
                          />
                        </td>
                        <td colspan={columns - 2}></td>
                      </tr>
                      {#each group.pivots as pivot (pivot.id)}
                        {@render pivotRows(pivot, 1, !open, errs)}
                      {/each}
                    {/each}
                    {#each rows.pivots as pivot (pivot.id)}
                      {@render pivotRows(pivot, 0, false, errs)}
                    {/each}
                    {#if rows.idle.length}
                      <tr class="border-t border-line">
                        <td colspan={columns} class="py-1.5 pl-8">
                          <span class="flex items-center gap-1 text-xs text-ink-muted">
                            {@render toggle(
                              `Irrigation systems with no crop on ${farm.name}`,
                              idleOpen,
                              () => (opened[idleKey] = !idleOpen),
                            )}
                            {count(rows.idle.length, 'system')} with no crop this season
                          </span>
                        </td>
                      </tr>
                      {#each rows.idle as pivot (pivot.id)}
                        {@render pivotRows(pivot, 0, !idleOpen, errs)}
                      {/each}
                    {/if}
                  </tbody>
                </table>
              </div>
            </section>
          {/if}
        {/each}

        <div
          class="sticky bottom-0 z-20 -mx-4 flex items-center gap-3 border-t border-line bg-surface/95 px-4 py-3 backdrop-blur"
        >
          <Button type="submit" disabled={processing}>Save {formatDate(date)}</Button>
          <p class="text-sm text-ink-muted">
            {#if Object.keys(errs).length}<span class="text-status-irrigate-ink"
                >Nothing was saved. Please correct the highlighted entries and save again.</span
              >
            {:else if isDirty || dirty}You have unsaved changes{:else}Leave rain blank to use the modeled rain. Enter 0
              if your gauge showed no rain.{/if}
          </p>
        </div>
      {/snippet}
    </Form>
  {/key}
{/if}
