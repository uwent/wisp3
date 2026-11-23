<script lang="ts" module>
  import type { TimelineInput } from '@/lib/timeline'

  export type TimelinePlanting = TimelineInput & {
    plant_name: string
    variety: string | null
    area_acres: number | null
    plot_length_ft: number | null
    plot_width_ft: number | null
  }
</script>

<script lang="ts" generics="T extends TimelinePlanting">
  import { Link, router } from '@inertiajs/svelte'
  import { DropdownMenu } from 'bits-ui'

  import { menuContent, menuItem } from '@/lib/components/menu'
  import { cropName, plantingWhen, plotSize, seasonDates } from '@/lib/plantings'
  import { timeline } from '@/lib/timeline'
  import type { Units } from '@/lib/units'
  import type { PlantingSummary } from '@/types/serializers'

  // A field's plantings for one season as bars across it, like a Gantt chart,
  // each named by its crop and when it is:
  // plots in season together in rows of their own, successions along one row. Each bar opens its
  // planting: href (its page), onselect (its form), or with both a small menu offering each (Setup's
  // bars: the page or the form). status colors a bar's dot by its planting's status today; current
  // marks the planting whose page this is.
  let {
    plantings,
    year,
    today,
    units,
    label,
    onselect,
    href,
    status = {},
    current,
  }: {
    plantings: T[]
    year: number
    today: string
    units: Units
    /** What the timeline is, for screen readers: "Plantings on North field, 2026" */
    label: string
    onselect?: (planting: T) => void
    href?: (planting: T) => string
    status?: Record<number, PlantingSummary['status']>
    current?: number
  } = $props()

  const layout = $derived(timeline(plantings, year, today))
  const describe = (p: T) => [cropName(p), seasonDates(p), plotSize(p, units) ?? 'whole field'].join(', ')
  // What the bar doesn't show, for screen readers after its visible text (which its name must contain)
  const more = (p: T) =>
    [p.variety && `(${p.variety})`, p.partial ? `part of the field, ${plotSize(p, units)}` : 'whole field']
      .filter(Boolean)
      .join(', ')
  const dots: Record<string, string> = {
    full: 'bg-status-full',
    ok: 'bg-status-ok',
    caution: 'bg-status-caution',
    irrigate: 'bg-status-irrigate',
    no_stress: 'bg-status-ok',
    stress_coming: 'bg-status-caution',
    stressed: 'bg-status-irrigate',
  }
  const ended = (p: T) => p.end_date < today
  // A bar's menu opens under the bar where it was clicked (a bar can span the whole season), centred
  // on the pointer; opened from the keyboard, under the bar's start. The anchor is a point on the
  // bar's bottom edge, measured from the bar each time, so it follows the page as it scrolls.
  let pointer = $state<{ id: number; bar: HTMLElement; offset: number } | null>(null)
  function pointAt(id: number, event: PointerEvent) {
    const bar = event.currentTarget as HTMLElement
    pointer = { id, bar, offset: event.clientX - bar.getBoundingClientRect().left }
  }
  function anchorFor(id: number) {
    if (pointer?.id !== id) return null
    const { bar, offset } = pointer
    return {
      getBoundingClientRect: () => {
        const rect = bar.getBoundingClientRect()
        return new DOMRect(rect.left + offset, rect.top, 0, rect.height)
      },
    }
  }
</script>

<div class="text-xs">
  <div class="relative h-5 border-b border-line text-ink-muted" aria-hidden="true">
    {#each layout.months as month (month.left)}
      <span
        class="absolute top-0 truncate border-l border-line pl-1"
        style:left="{month.left}%"
        style:width="{month.width}%">{month.label}</span
      >
    {/each}
  </div>
  <ul class="relative py-1" style:height="{layout.rows * 2 + 0.5}rem" aria-label={label}>
    {#if layout.today !== null}
      <li
        class="absolute inset-y-0 w-px bg-status-irrigate/60"
        style:left="{layout.today}%"
        title="Today"
        aria-hidden="true"
      ></li>
    {/if}
    {#each layout.bars as bar (bar.planting.id)}
      {@const p = bar.planting}
      {@const classes = `absolute flex h-7 min-w-7 items-center gap-1 overflow-hidden rounded-md border px-1.5 text-left
        whitespace-nowrap focus-visible:outline-2 focus-visible:outline-brand-500
        ${p.partial ? 'border-dashed' : ''}
        ${current === p.id ? 'border-brand-600 bg-brand-100 font-medium ring-1 ring-brand-600' : ended(p) ? 'border-line bg-surface text-ink-muted hover:border-brand-500' : 'border-brand-500/60 bg-brand-50 hover:border-brand-600'}`}
      <li>
        {#snippet inside(verb?: string)}
          {#if verb}<span class="sr-only">{verb}</span>{/if}
          {#if status[p.id]}<span class="size-2 shrink-0 rounded-full {dots[status[p.id]!]}" aria-hidden="true"
            ></span>{/if}
          <span class="truncate" data-search-text>{p.plant_name}</span>
          <span class="truncate text-xs text-ink-muted">{plantingWhen(p, today)}</span>
          <span class="sr-only">{`, ${more(p)}`}</span>
        {/snippet}
        {#if href && onselect}
          <DropdownMenu.Root>
            <DropdownMenu.Trigger
              class={classes}
              style="left: {bar.left}%; width: {bar.width}%; top: {bar.row * 2 + 0.25}rem"
              title={describe(p)}
              onpointerdown={(event: PointerEvent) => pointAt(p.id, event)}
              onkeydown={() => (pointer = null)}>{@render inside()}</DropdownMenu.Trigger
            >
            <DropdownMenu.Portal>
              <DropdownMenu.Content
                class={menuContent}
                sideOffset={4}
                customAnchor={anchorFor(p.id)}
                align={pointer?.id === p.id ? 'center' : 'start'}
                preventScroll={false}
              >
                <DropdownMenu.Item class={menuItem} onSelect={() => router.visit(href(p))}>
                  View this planting
                </DropdownMenu.Item>
                <DropdownMenu.Item class={menuItem} onSelect={() => onselect(p)}>Edit planting</DropdownMenu.Item>
              </DropdownMenu.Content>
            </DropdownMenu.Portal>
          </DropdownMenu.Root>
        {:else if href}
          <Link
            href={href(p)}
            class={classes}
            style="left: {bar.left}%; width: {bar.width}%; top: {bar.row * 2 + 0.25}rem"
            aria-current={current === p.id ? 'page' : undefined}
            title={describe(p)}>{@render inside()}</Link
          >
        {:else}
          <button
            type="button"
            class={classes}
            style="left: {bar.left}%; width: {bar.width}%; top: {bar.row * 2 + 0.25}rem"
            title={describe(p)}
            onclick={() => onselect?.(p)}>{@render inside('Edit ')}</button
          >
        {/if}
      </li>
    {/each}
  </ul>
</div>
