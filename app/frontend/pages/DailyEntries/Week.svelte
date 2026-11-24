<script lang="ts">
  import { untrack } from 'svelte'
  import { Form, Link } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import DailyViewSwitch from '@/lib/components/DailyViewSwitch.svelte'
  import IrrigationCalculatorDialog from '@/lib/components/IrrigationCalculatorDialog.svelte'
  import {
    cellErrors,
    changes,
    fieldAmounts,
    irrigationKey,
    keyMove,
    leavesBox,
    nextCell,
    overwriteMessage,
    rainKey,
    savedTexts,
    settledText,
    weekOf,
    type Cell,
    type WeekFarm,
    type WeekIrrigationRow,
  } from '@/lib/dailyWeek'
  import { addDays, formatDate, today as todayDate } from '@/lib/dates'
  import { systemName } from '@/lib/geo'
  import { count } from '@/lib/text'
  import { confirmUnsavedChanges } from '@/lib/unsaved.svelte'
  import { currentUnits } from '@/lib/units'
  import { dailyEntries, dailyEntryWeeks, newQuickSetup } from '@/routes'

  let { date, dates, farms, has_systems }: { date: string; dates: string[]; farms: WeekFarm[]; has_systems: boolean } =
    $props()

  const units = $derived(currentUnits())
  const today = todayDate()
  const week = $derived(weekOf(date))
  const before = $derived(weekOf(addDays(date, -7)))
  const after = $derived(weekOf(addDays(date, 7)))
  // One week ahead at most: planned irrigation
  const canGoOn = $derived(date < today)

  // What's typed in every cell; set from what's saved, again after a save, not whenever the page's
  // data changes
  let texts = $state<Record<string, string>>(untrack(() => savedTexts(farms, dates, units)))
  let saves = $state(0)
  $effect(() => {
    void [date, saves]
    untrack(() => {
      texts = savedTexts(farms, dates, units)
    })
  })

  const changed = $derived(changes(farms, dates, texts, units))
  const changedKeys = $derived(new Set(changed.cells.map((cell) => cell.key)))
  const dirty = $derived(changed.cells.length > 0)
  confirmUnsavedChanges(
    () => dirty,
    () => document.getElementById('daily-week-form'),
  )

  /** A cell's own complaint while what's typed can't be read (the form won't submit) */
  function unreadable(key: string): string | null {
    const parsed = units.parse('depth', texts[key] ?? '')
    return parsed.ok ? null : parsed.error
  }
  // The calculator's days for a system: those taking irrigation, each with its fields and their acres;
  // it starts on today, else the latest of them
  function calculatorDays(row: WeekIrrigationRow) {
    return dates
      .map((day, i) => ({
        date: day,
        active: row.days[i].active,
        // Fields and plots (a field growing only plots) can share an id: numbered here instead
        fields: row.days[i].fields.map((f, n) => ({ id: n, name: f.name, acres: f.acres ?? null })),
      }))
      .filter((day) => day.active)
  }
  const calculatorStart = (row: WeekIrrigationRow) => {
    const days = calculatorDays(row)
    return (days.find((day) => day.date === today) ?? days.findLast((day) => day.date <= today) ?? days[0])?.date
  }
  /** The calculator's inches, typed into the day's cell */
  function applyCalculated(row: WeekIrrigationRow, inches: number, day: string) {
    texts[irrigationKey(row, day)] = units.input('depth', inches)
  }

  function validity(box: HTMLInputElement, message: string | null) {
    box.setCustomValidity(message ?? '')
    return { update: (next: string | null) => box.setCustomValidity(next ?? '') }
  }

  // Arrow keys move between the cells of a farm's grid (Enter moves down), skipping those that take
  // no value that day
  function onKeydown(event: KeyboardEvent) {
    const box = event.target
    if (!(box instanceof HTMLInputElement) || box.dataset.row === undefined) return
    const move = keyMove(event.key)
    if (!move || event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return
    if (event.key === 'Enter') event.preventDefault() // not a save
    if (!leavesBox(move, box.selectionStart, box.selectionEnd, box.value.length)) return
    const table = box.closest('table')
    if (!table) return
    const boxes = [...table.querySelectorAll<HTMLInputElement>('input[data-row]:not(:disabled)')]
    const at = (input: HTMLInputElement): Cell => ({ row: Number(input.dataset.row), col: Number(input.dataset.col) })
    const target = nextCell(boxes.map(at), at(box), move)
    if (!target) return
    event.preventDefault()
    const next = boxes.find(
      (input) => input.dataset.row === String(target.row) && input.dataset.col === String(target.col),
    )
    next?.focus()
    next?.select()
  }

  const dayName = (day: string) => formatDate(day, { weekday: true })
  // The first column stays in view while the grid scrolls sideways (phones)
  const nameCell = 'sticky left-0 z-10 min-w-44 bg-surface-raised py-1.5 pr-2 pl-3 text-left align-middle'
  const box =
    'block w-full min-w-0 rounded-md px-2 py-1.5 text-center text-sm shadow-sm focus:border-brand-500 focus:ring-brand-500 disabled:cursor-not-allowed disabled:bg-surface disabled:shadow-none'
</script>

<svelte:head><title>Daily entry: week · WISP</title></svelte:head>

<div class="flex flex-wrap items-end justify-between gap-3">
  <div>
    <h1 class="text-2xl font-semibold">Daily entry</h1>
    <p class="text-sm text-ink-muted">Rain and irrigation for all your irrigation systems, a week at a time.</p>
  </div>
  <div class="flex flex-wrap items-center gap-3">
    <DailyViewSwitch view="week" {date} />
    <nav class="flex items-center gap-1 text-sm" aria-label="Weeks">
      <Link
        href={dailyEntryWeeks.show({ query: { date: before.end } })}
        class="rounded-md border border-line bg-surface-raised px-3 py-1.5 hover:bg-surface"
        aria-label="Previous week, {before.label}"
        ><span aria-hidden="true">‹</span><span class="hidden sm:inline">{` ${before.label}`}</span></Link
      >
      <span class="px-2 font-medium">{week.label}</span>
      {#if canGoOn}
        <Link
          href={dailyEntryWeeks.show({ query: { date: after.end } })}
          class="rounded-md border border-line bg-surface-raised px-3 py-1.5 hover:bg-surface"
          aria-label="Next week, {after.label}"
          ><span class="hidden sm:inline">{`${after.label} `}</span><span aria-hidden="true">›</span></Link
        >
      {/if}
    </nav>
  </div>
</div>

{#if farms.length === 0}
  <section
    class="rounded-lg border border-dashed border-line bg-surface-raised px-6 py-10 text-center text-sm text-ink-muted"
  >
    {#if !has_systems}
      You haven't added an irrigation system yet.
      <Link href={newQuickSetup()} class="text-brand-600 underline underline-offset-2"
        >Set up your first irrigation system</Link
      > to start entering rain and irrigation.
    {:else}
      No field has a crop in season during {week.label}. The week shows fields with a crop growing; the Day view has
      every field.
    {/if}
  </section>
{:else}
  {#key date}
    <Form
      id="daily-week-form"
      action={dailyEntryWeeks.update()}
      class="space-y-6"
      options={{ preserveScroll: true }}
      onBefore={() => {
        const message = overwriteMessage(changed.cells)
        if (message && !confirm(message)) return false
      }}
      onSuccess={() => saves++}
    >
      {#snippet children({ errors, processing })}
        {@const problems = cellErrors(farms, dates, errors as Record<string, string | string[]>)}
        <input type="hidden" name="date" value={date} />
        {#each changed.inputs as input, i (i)}
          <input type="hidden" name={input.name} value={input.value} />
        {/each}
        <p class="text-xs text-ink-muted">
          Rain typed for an irrigation group or system, and irrigation for a system, fills in each of its fields in
          season that day. Plots, soil moisture and cover readings are in the Day view: each date links to it.
        </p>

        {#each farms as farm (farm.id)}
          {@const rainRows = farm.rain_rows.length}
          <section aria-labelledby="farm-{farm.id}">
            <div class="relative overflow-x-auto rounded-lg border border-line bg-surface-raised">
              <!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
              <table class="w-full min-w-3xl text-sm" onkeydown={onKeydown}>
                <thead class="text-xs text-ink-muted">
                  <tr>
                    <th id="farm-{farm.id}" scope="col" class="{nameCell} text-sm font-medium text-ink">{farm.name}</th>
                    <!-- The irrigation rows' calculators: their own cell, so a row's header is just its name -->
                    <td class="w-8"></td>
                    {#each dates as day (day)}
                      <th scope="col" class="px-1 py-1.5 text-center font-medium">
                        <Link
                          href={dailyEntries.show({ query: { date: day } })}
                          class="inline-block rounded-sm px-1 hover:text-ink hover:underline {day === today
                            ? 'text-ink'
                            : ''}"
                          title="Open {dayName(day)} in the Day view"
                        >
                          <span class="block">{formatDate(day, { weekday: true }).split(',')[0]}</span>
                          <span class="block">{formatDate(day)}</span>
                        </Link>
                      </th>
                    {/each}
                  </tr>
                </thead>
                <tbody>
                  <tr class="border-t border-line bg-surface">
                    <th scope="colgroup" colspan={dates.length + 2} class="px-3 py-1 text-left text-xs font-medium">
                      Rain ({units.label('depth')})
                    </th>
                  </tr>
                  {#each farm.rain_rows as row, r (row.key)}
                    <tr class="border-t border-line/60">
                      <th scope="row" class="{nameCell} font-normal">
                        <span class="block font-medium"
                          >{row.kind === 'system'
                            ? systemName({ name: row.name, kind_name: row.kind_name ?? '' })
                            : row.name}</span
                        >
                        <span class="block text-xs text-ink-muted"
                          >{row.kind === 'group'
                            ? `Irrigation group · ${count(row.systems ?? 0, 'system')}`
                            : 'Irrigation system'}</span
                        >
                      </th>
                      <td></td>
                      {#each dates as day, c (day)}
                        {@const cell = row.days[c]}
                        {@const key = rainKey(row, day)}
                        {@const ahead = day > today}
                        {@const replacing = cell.varies && changedKeys.has(key)}
                        {@const problem = problems[key]}
                        {@const id = `cell-${key.replaceAll(':', '-')}`}
                        <td class="px-1 py-1">
                          <input
                            {id}
                            type="text"
                            inputmode="decimal"
                            autocomplete="off"
                            class="{box} {problem
                              ? 'border-status-irrigate'
                              : replacing
                                ? 'border-status-caution ring-2 ring-status-caution'
                                : ''}"
                            data-row={r}
                            data-col={c}
                            data-unit={units.label('depth')}
                            aria-label="{row.name} rain, {dayName(day)}"
                            aria-invalid={problem ? 'true' : undefined}
                            aria-describedby={problem || replacing ? `${id}-note` : undefined}
                            disabled={!cell.active || ahead}
                            placeholder={ahead && cell.active ? '—' : cell.varies ? 'varies' : ''}
                            title={cell.varies
                              ? fieldAmounts(cell, units)
                              : ahead && cell.active
                                ? 'Rain can be entered once the day has come'
                                : undefined}
                            bind:value={texts[key]}
                            onblur={() => (texts[key] = settledText(texts[key] ?? '', units))}
                            use:validity={unreadable(key)}
                          />
                          {#if problem || replacing}
                            <span id="{id}-note" class="sr-only"
                              >{problem
                                ? problem.message
                                : `Replaces different amounts: ${fieldAmounts(cell, units)}`}</span
                            >
                          {/if}
                        </td>
                      {/each}
                    </tr>
                  {/each}
                  <tr class="border-t border-line bg-surface">
                    <th scope="colgroup" colspan={dates.length + 2} class="px-3 py-1 text-left text-xs font-medium">
                      Irrigation ({units.label('depth')})
                    </th>
                  </tr>
                  {#each farm.irrigation_rows as row, i (row.key)}
                    {@const start = calculatorStart(row)}
                    <tr class="border-t border-line/60">
                      <th scope="row" class="{nameCell} font-medium">{systemName(row)}</th>
                      <td class="py-1 align-middle">
                        {#if start}
                          <IrrigationCalculatorDialog
                            system={row}
                            date={start}
                            days={calculatorDays(row)}
                            onapply={(inches, _fieldIds, day) => applyCalculated(row, inches, day)}
                          />
                        {/if}
                      </td>
                      {#each dates as day, c (day)}
                        {@const cell = row.days[c]}
                        {@const key = irrigationKey(row, day)}
                        {@const replacing = cell.varies && changedKeys.has(key)}
                        {@const problem = problems[key]}
                        {@const id = `cell-${key.replaceAll(':', '-')}`}
                        <td class="px-1 py-1">
                          <input
                            {id}
                            type="text"
                            inputmode="decimal"
                            autocomplete="off"
                            class="{box} {problem
                              ? 'border-status-irrigate'
                              : replacing
                                ? 'border-status-caution ring-2 ring-status-caution'
                                : ''}"
                            data-row={rainRows + i}
                            data-col={c}
                            data-unit={units.label('depth')}
                            aria-label="{row.name} irrigation, {dayName(day)}"
                            aria-invalid={problem ? 'true' : undefined}
                            aria-describedby={problem || replacing ? `${id}-note` : undefined}
                            disabled={!cell.active}
                            placeholder={cell.varies ? 'varies' : ''}
                            title={cell.varies ? fieldAmounts(cell, units) : undefined}
                            bind:value={texts[key]}
                            onblur={() => (texts[key] = settledText(texts[key] ?? '', units))}
                            use:validity={unreadable(key)}
                          />
                          {#if problem || replacing}
                            <span id="{id}-note" class="sr-only"
                              >{problem
                                ? problem.message
                                : `Replaces different amounts: ${fieldAmounts(cell, units)}`}</span
                            >
                          {/if}
                        </td>
                      {/each}
                    </tr>
                  {/each}
                </tbody>
              </table>
            </div>
          </section>
        {/each}

        <div class="sticky bottom-0 z-20 -mx-4 space-y-2 border-t border-line bg-surface/95 px-4 py-3 backdrop-blur-sm">
          {#if Object.keys(problems).length}
            <div class="text-sm text-status-irrigate-ink" role="alert">
              <p>Nothing was saved. Please correct these and save again:</p>
              <ul class="list-disc pl-5">
                {#each Object.entries(problems) as [key, problem] (key)}
                  <li>
                    <a href="#cell-{key.replaceAll(':', '-')}" class="underline"
                      >{problem.label}, {dayName(problem.date)}</a
                    >{`: ${problem.message}`}
                  </li>
                {/each}
              </ul>
            </div>
          {/if}
          <div class="flex items-center gap-3">
            <Button type="submit" disabled={processing}>Save {week.label}</Button>
            <p class="text-sm text-ink-muted">
              {#if dirty}You have unsaved changes{:else}Leave rain blank to use the modeled rain. Enter 0 if your gauge
                showed no rain.{/if}
            </p>
          </div>
        </div>
      {/snippet}
    </Form>
  {/key}
{/if}
