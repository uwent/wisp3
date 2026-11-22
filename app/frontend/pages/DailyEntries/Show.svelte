<script lang="ts">
  import { onMount, untrack } from 'svelte'
  import { Form, Link, router } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import DailyViewSwitch, { DAILY_VIEW_KEY } from '@/lib/components/DailyViewSwitch.svelte'
  import IrrigationCalculator from '@/lib/components/IrrigationCalculator.svelte'
  import NumberField from '@/lib/components/NumberField.svelte'
  import {
    farmRows,
    fieldBox,
    fieldBoxes,
    fieldHasEntry,
    fieldRowBoxes,
    inSeason,
    pivotHasEntry,
    plotBox,
    plots,
    rainFields,
    rainNote,
    rainView,
    rowAmount,
    savedIrrigation,
    systemBoxes,
    wholeField,
    yesterdayBoxes,
    type DayFarm,
    type DayField,
    type DayPivot,
    type DayPlanting,
  } from '@/lib/dailyEntry'
  import { addDays, formatDate, today as todayDate } from '@/lib/dates'
  import { systemName } from '@/lib/geo'
  import { common } from '@/lib/irrigation'
  import { cropName, plotSize } from '@/lib/plantings'
  import { readStored, writeStored } from '@/lib/storage'
  import { count } from '@/lib/text'
  import { confirmUnsavedChanges } from '@/lib/unsaved.svelte'
  import { currentUnits } from '@/lib/units'
  import {
    dailyEntries,
    dailyEntryWeeks,
    fields as fieldRoutes,
    newQuickSetup,
    plantings as plantingRoutes,
  } from '@/routes'

  let { date, farms }: { date: string; farms: DayFarm[] } = $props()

  const units = $derived(currentUnits())
  const today = todayDate()

  // Day | Week (Phase 9 §6): the Day switch (view=day) remembers the day view; daily entry reached
  // with no date or view (the nav's link) goes on to the week when that was the last chosen
  onMount(() => {
    const query = new URLSearchParams(location.search)
    if (query.get('view') === 'day') writeStored(DAILY_VIEW_KEY, 'day')
    else if (!query.has('date') && readStored(DAILY_VIEW_KEY) === 'week')
      router.visit(dailyEntryWeeks.show().url, { replace: true })
  })

  // Typed values not yet saved: set by any input, cleared by a successful save
  let dirty = $state(false)
  const unsaved = confirmUnsavedChanges(
    () => dirty,
    () => document.getElementById('daily-entry-form'),
  )

  /** Goes to another date, asking first if there are unsaved values; false if the user stayed */
  function go(to: string): boolean {
    if (dirty && !confirm(unsaved.message())) return false
    dirty = false
    router.get(dailyEntries.show().url, { date: to })
    return true
  }

  const allPivots = $derived(farms.flatMap((farm) => farm.pivots))
  const allFields = $derived(allPivots.flatMap((pivot) => pivot.fields))

  // Each field's rain and each field's and plot's irrigation, as saved: what the rows show and
  // fill, submitted from here. Reset for another date and after a save, not whenever the page's
  // data changes (a reload for another reason keeps what's typed).
  const savedRain = (fields: DayField[]) => Object.fromEntries(fields.map((f) => [f.id, f.entry?.rain_in ?? null]))
  let rain = $state<Record<number, number | null>>(untrack(() => savedRain(allFields)))
  let irrigation = $state<Record<string, number | null>>(untrack(() => savedIrrigation(allPivots)))
  let saves = $state(0)
  // Only another date or a save resets them: props reloaded for anything else (the calculator saving
  // a pump capacity) re-run effects that read the props directly, and a derived string doesn't change
  const resetKey = $derived(`${date}:${saves}`)
  $effect(() => {
    void resetKey
    untrack(() => {
      rain = savedRain(allFields)
      irrigation = savedIrrigation(allPivots)
      varied = {}
    })
  })

  // A parent row showing "varies" keeps its children's amounts from before the first keystroke, so
  // typing there and then clearing the box puts them back rather than blanking every one
  let varied: Record<string, Record<string, number | null>> = {}
  function fillRow(
    key: string,
    values: Record<string | number, number | null>,
    keys: (string | number)[],
    value: number | null,
  ) {
    const before = varied[key]
    if (value === null && before) {
      Object.assign(values, before)
      delete varied[key]
    } else {
      if (value !== null && !before && common(keys.map((k) => values[k] ?? null)).varies)
        varied[key] = Object.fromEntries(keys.map((k) => [k, values[k] ?? null]))
      for (const k of keys) values[k] = value
    }
    dirty = true
  }

  function fillIrrigation(boxes: string[], value: number | null) {
    for (const box of boxes) irrigation[box] = value
    dirty = true
  }

  /** The calculator's fields: each with the acres its run hours spread over (its crop's area, else the field's) */
  const calculatorFields = (fields: DayField[]) =>
    fields.map((field) => ({
      id: field.id,
      name: field.name,
      acres: wholeField(field)?.area_acres ?? field.area_acres,
    }))
  function applyToFields(pivot: DayPivot, inches: number, fieldIds: number[]) {
    for (const field of pivot.fields.filter((f) => fieldIds.includes(f.id))) fillIrrigation(fieldBoxes(field), inches)
  }

  // "Same as yesterday": the day before's amounts, while nothing is entered for the system this day
  const dayBefore = $derived(date === today ? 'yesterday' : 'the day before')
  const offersYesterday = (pivot: DayPivot) =>
    pivot.yesterday !== null && systemBoxes(pivot).every((box) => irrigation[box] == null)
  function sameAsYesterday(pivot: DayPivot) {
    const boxes = yesterdayBoxes(pivot)
    if (!boxes) return
    Object.assign(irrigation, boxes)
    dirty = true
  }

  /** A rain box's placeholder: the fields' shared amount (modeled, when none is entered), or varies */
  // (modeled says so under the box: in the box it crowds the amount out on a phone)
  function rainPlaceholder(view: ReturnType<typeof rainView>) {
    if (view.varies) return 'varies'
    return view.shown === null ? '' : units.format('depth', view.shown, { unit: false })
  }
  const showsModeled = (view: ReturnType<typeof rainView>) =>
    view.value === null && view.modeled && !view.varies && view.shown !== null

  /** The first error among some fields' values (rain is entered on a group's or system's row) */
  const firstError = (errs: Record<string, string | string[]>, keys: string[]) =>
    keys.map((key) => errs[key]).find(Boolean)

  // Collapsed rows. A pivot group's or pivot's choice is remembered in this browser; the rest
  // (fields with no crop, plots, pivots with nothing in season) start closed unless something was
  // entered there that day
  const STORAGE_KEY = 'wisp.dailyEntry.collapsed'
  const stored = readStored(STORAGE_KEY)
  let collapsed = $state<Record<string, boolean>>(
    stored && typeof stored === 'object' ? (stored as Record<string, boolean>) : {},
  )
  let opened = $state<Record<string, boolean>>({})
  function remember(key: string, isCollapsed: boolean) {
    collapsed[key] = isCollapsed
    // Not remembered when storage is blocked: it still works on this page
    writeStored(STORAGE_KEY, Object.fromEntries(Object.entries(collapsed).filter(([, closed]) => closed)))
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

  // Indents for each level's name cell, with room for its expand toggle; smaller steps on a phone, so
  // the boxes stay in view
  const indent = ['pl-6 sm:pl-8', 'pl-9 sm:pl-13', 'pl-12 sm:pl-18', 'pl-15 sm:pl-23']
  // Names stay in view while the table scrolls sideways (phones); each row sets its background
  const nameCell = 'sticky left-0 z-10 min-w-28 py-1.5 pr-2 text-left sm:min-w-40'
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

{#snippet modeledNote(view: ReturnType<typeof rainView>)}
  {#if showsModeled(view)}<p class="mt-0.5 text-center text-xs text-ink-muted">modeled</p>{/if}
{/snippet}

{#snippet coverCell(planting: DayPlanting, label: string, errs: Record<string, string | string[]>)}
  {#if planting.cover}
    {@const cover = planting.cover}
    <NumberField
      hideLabel
      center
      label="{cover.kind === 'lai' ? 'LAI' : 'Percent cover'} on {label}{cover.due ? ' (due)' : ''}"
      name="canopy[{planting.id}]"
      value={cover.value}
      error={errs[`canopy.${planting.id}`]}
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
  {@const amount = rowAmount(fieldRowBoxes(field), irrigation)}
  {@const rainVaries = inSeason(field) && rainView(pivot.fields.filter(inSeason), rain).varies}
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
    <td class="w-24 px-1 py-1.5 sm:w-36 sm:px-2">
      <!-- Rain is entered on the system's row; the field's own shows here when they differ -->
      <input type="hidden" name="fields[{field.id}][rain_in]" value={rain[field.id] ?? ''} />
      {#if rainVaries}
        <span class="block py-2 text-xs text-ink-muted"
          >{rain[field.id] != null
            ? units.format('depth', rain[field.id], { unit: false })
            : field.rain_model != null
              ? `${units.format('depth', field.rain_model, { unit: false })} modeled`
              : ''}</span
        >
      {/if}
    </td>
    <td class="w-24 px-1 py-1.5 sm:w-36 sm:px-2">
      <input type="hidden" name="fields[{field.id}][irrigation_in]" value={irrigation[fieldBox(field.id)] ?? ''} />
      <NumberField
        hideLabel
        center
        id="field-{field.id}-irrigation"
        label="Irrigation on {field.name}"
        quantity="depth"
        precision={units.digits('depth')}
        bind:value={() => amount.value, (value) => fillRow(`field-${field.id}`, irrigation, fieldBoxes(field), value)}
        placeholder={amount.varies ? 'varies' : ''}
        error={errs[`fields.${field.id}.irrigation_in`]}
      />
    </td>
    <td class="w-20 px-1 py-1.5 sm:w-28 sm:px-2">
      {#if whole || !inSeason(field)}
        <NumberField
          hideLabel
          center
          label="Soil moisture reading on {field.name}"
          name="fields[{field.id}][soil_moisture_pct]"
          value={field.entry?.soil_moisture_pct ?? null}
          error={errs[`fields.${field.id}.soil_moisture_pct`]}
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
      <td class="w-20 px-1 py-1.5 sm:w-28 sm:px-2"
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
      <td class="px-1 py-1.5 sm:px-2"></td>
      <td class="px-1 py-1.5 sm:px-2">
        <input type="hidden" name="plantings[{plot.id}][irrigation_in]" value={irrigation[plotBox(plot.id)] ?? ''} />
        <NumberField
          hideLabel
          center
          id="plot-{plot.id}-irrigation"
          label="Irrigation on {plotLabel} on {field.name}"
          quantity="depth"
          precision={units.digits('depth')}
          bind:value={irrigation[plotBox(plot.id)]}
          error={errs[`plantings.${plot.id}.irrigation_in`]}
        />
      </td>
      <td class="px-1 py-1.5 sm:px-2">
        <NumberField
          hideLabel
          center
          label="Soil moisture reading on {plotLabel} on {field.name}"
          name="plantings[{plot.id}][soil_moisture_pct]"
          value={plot.entry?.soil_moisture_pct ?? null}
          error={errs[`plantings.${plot.id}.soil_moisture_pct`]}
        />
      </td>
      {#if anyCover}
        <td class="px-1 py-1.5 sm:px-2">{@render coverCell(plot, `${plotLabel} on ${field.name}`, errs)}</td>
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
  {@const rainShared = rainView(growing, rain)}
  {@const amount = rowAmount(systemBoxes(pivot), irrigation)}
  <tr class="border-t border-line bg-surface align-top" {hidden}>
    <th scope="row" class="{nameCell} bg-surface {indent[depth]}">
      <span class="flex items-start gap-1">
        {@render toggle(`Fields on ${pivot.name}`, open, () => remember(key, open))}
        <span>
          <span class="font-medium">{systemName(pivot)}</span>
          <span class="block text-xs font-normal text-ink-muted">{count(pivot.fields.length, 'field')}</span>
        </span>
      </span>
    </th>
    <td class="min-w-20 px-1 py-1.5 sm:px-2">
      {#if growing.length}
        <NumberField
          hideLabel
          center
          id="pivot-{pivot.id}-rain"
          label="Rain on {pivot.name}"
          quantity="depth"
          precision={units.digits('depth')}
          bind:value={
            () => rainShared.value,
            (value) =>
              fillRow(
                `rain-pivot-${pivot.id}`,
                rain,
                growing.map((f) => f.id),
                value,
              )
          }
          placeholder={rainPlaceholder(rainShared)}
          error={firstError(
            errs,
            growing.map((f) => `fields.${f.id}.rain_in`),
          )}
        />
        {@render modeledNote(rainShared)}
      {/if}
    </td>
    <td class="px-1 py-1.5 sm:px-2" colspan={columns - 2}>
      {#if growing.length}
        <div class="flex flex-wrap items-start gap-x-3 gap-y-1">
          <div class="w-24 sm:w-32">
            <NumberField
              hideLabel
              center
              id="pivot-{pivot.id}-irrigation"
              label="Irrigation by {pivot.name}"
              quantity="depth"
              precision={units.digits('depth')}
              bind:value={
                () => amount.value, (value) => fillRow(`pivot-${pivot.id}`, irrigation, systemBoxes(pivot), value)
              }
              placeholder={amount.varies ? 'varies' : ''}
            >
              {#snippet trailing()}
                <IrrigationCalculator
                  system={pivot}
                  fields={calculatorFields(growing)}
                  {date}
                  onapply={(inches, fieldIds) => applyToFields(pivot, inches, fieldIds)}
                />
              {/snippet}
            </NumberField>
          </div>
          {#if offersYesterday(pivot)}
            <button
              type="button"
              class="py-2 text-xs text-brand-600 hover:underline"
              aria-label="Same as {dayBefore} for {pivot.name}"
              onclick={() => sameAsYesterday(pivot)}>Same as {dayBefore}</button
            >
          {/if}
        </div>
      {/if}
    </td>
  </tr>
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
  <div class="flex flex-wrap items-center gap-3">
    <DailyViewSwitch view="day" {date} />
    <div class="flex items-center gap-1">
      <Button variant="secondary" class="px-3" onclick={() => go(addDays(date, -1))} aria-label="Previous day">‹</Button
      >
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
      id="daily-entry-form"
      action={dailyEntries.update()}
      class="space-y-6"
      options={{ preserveScroll: true }}
      oninput={() => (dirty = true)}
      onchange={() => (dirty = true)}
      onSuccess={() => {
        dirty = false
        saves++
      }}
    >
      {#snippet children({ errors, processing, isDirty })}
        {@const errs = errors as Record<string, string | string[]>}
        <input type="hidden" name="date" value={date} />
        <div class="flex flex-wrap items-baseline justify-between gap-2">
          <div>
            <h2 class="text-lg font-medium">{formatDate(date, { weekday: true, year: true })}</h2>
            {#if date === addDays(today, -1)}
              <p class="text-xs text-ink-muted">Yesterday: rain read from your gauge this morning goes here.</p>
            {/if}
          </div>
          <p class="text-xs text-ink-muted">
            Rain goes on an irrigation group or system and fills in its fields. Irrigation typed on a system fills in
            its fields and plots; change any of them before saving.
          </p>
        </div>

        {#each farms as farm (farm.id)}
          {@const rows = farmRows(farm)}
          {@const idleKey = `idle-farm-${farm.id}`}
          {@const idleOpen = shown(idleKey, rows.idle.some(pivotHasEntry))}
          {#if farm.pivots.length}
            <section class="space-y-2" aria-labelledby="farm-{farm.id}">
              <h3 id="farm-{farm.id}" class="font-medium text-ink-muted">
                {farm.name}{#if !farm.use_model_precip}<span class="text-xs font-normal"
                    >{' · only entered rain counts'}</span
                  >{/if}
              </h3>
              <div class="relative overflow-x-auto rounded-lg border border-line bg-surface-raised">
                <table class="w-full text-sm sm:min-w-xl">
                  <thead class="text-xs text-ink-muted">
                    <tr class="text-left">
                      <th class="sticky left-0 z-10 bg-surface-raised px-3 py-1.5 font-medium">System or field</th>
                      <th class="px-1 py-1.5 text-center font-medium sm:px-2">Rain ({units.label('depth')})</th>
                      <th class="px-1 py-1.5 text-center font-medium sm:px-2">Irrigation ({units.label('depth')})</th>
                      <th class="px-1 py-1.5 text-center font-medium sm:px-2">Soil moisture (%)</th>
                      {#if anyCover}<th class="px-1 py-1.5 text-center font-medium sm:px-2">{coverHeading}</th>{/if}
                    </tr>
                  </thead>
                  <tbody>
                    {#each rows.groups as group (group.id)}
                      {@const key = `group-${group.id}`}
                      {@const open = isOpen(key)}
                      {@const fields = rainFields(group.pivots)}
                      {@const rainShared = rainView(fields, rain)}
                      <tr class="border-t border-line bg-brand-50 align-top">
                        <th scope="row" class="{nameCell} bg-brand-50 {indent[0]}">
                          <span class="flex items-start gap-1">
                            {@render toggle(`Irrigation systems in ${group.name}`, open, () => remember(key, open))}
                            <span>
                              <span class="font-medium">{group.name}</span>
                              <span class="block text-xs font-normal text-ink-muted"
                                >{`Irrigation group · ${count(group.pivots.length, 'system')}`}{rainNote(
                                  group,
                                  farm,
                                )}</span
                              >
                            </span>
                          </span>
                        </th>
                        <td class="min-w-20 px-1 py-1.5 sm:px-2">
                          <NumberField
                            hideLabel
                            center
                            id="group-{group.id}-rain"
                            label="Rain on {group.name}"
                            quantity="depth"
                            precision={units.digits('depth')}
                            bind:value={
                              () => rainShared.value,
                              (value) =>
                                fillRow(
                                  `rain-group-${group.id}`,
                                  rain,
                                  fields.map((f) => f.id),
                                  value,
                                )
                            }
                            placeholder={rainPlaceholder(rainShared)}
                          />
                          {@render modeledNote(rainShared)}
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
