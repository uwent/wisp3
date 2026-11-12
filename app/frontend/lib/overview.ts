import type { PlantingSummary } from '@/types/serializers'

// The operation's farms, pivots and field cards (OperationOverview), as the dashboard and the map
// get them, and how the map orders and picks them

/**
 * A field and its plantings in season today, or the nearest this year (several on a field of plots,
 * PLAN.md Phase 8 G.11); empty without a planting this year
 */
export type FieldCard = { id: number; name: string; plantings: PlantingSummary[] }
/** weather_updating: a weather update for the pivot's cell is queued or running */
export type PivotGroup = {
  id: number
  name: string
  /** "Pivot", "Traveler" (Pivot::KIND_NAMES) */
  kind_name: string
  /** Its irrigation group (PivotGroup), if any */
  pivot_group_id: number | null
  weather_updating: boolean
  fields: FieldCard[]
}
export type FarmGroup<P extends PivotGroup = PivotGroup> = {
  id: number
  name: string
  /** Its irrigation groups */
  pivot_groups: { id: number; name: string }[]
  pivots: P[]
}

export type Status = NonNullable<PlantingSummary['status']>

/** Most urgent first */
export const STATUSES: Status[] = ['irrigate', 'caution', 'needs_canopy', 'ok', 'full']

/** The pivots whose weather is being updated, so the page waits for it to land (lib/poll.ts) */
export const updatingIds = (farms: FarmGroup[]) =>
  farms.flatMap((farm) => farm.pivots.filter((pivot) => pivot.weather_updating).map((pivot) => pivot.id))

export const anyUpdating = (farms: FarmGroup[]) => updatingIds(farms).length > 0

/** In season, with a status (not upcoming, ended, or waiting for weather) */
export const summaryActive = (summary: PlantingSummary | null) =>
  summary?.phase === 'active' && !summary.weather_pending && summary.status !== null

/**
 * Where a planting stands, most urgent first: in season by status (irrigate, caution, ok, full), in
 * season without one yet, then upcoming, season ended, and no crop (FieldStatuses.urgency)
 */
export function summaryUrgency(summary: PlantingSummary | null): number {
  const n = STATUSES.length
  if (!summary) return n + 3
  if (summary.phase === 'upcoming') return n + 1
  if (summary.phase === 'ended') return n + 2
  return summaryActive(summary) ? STATUSES.indexOf(summary.status!) : n
}

/** Days until the planting needs water (0 when it does now), or null if not within the forecast */
export function summaryDaysToIrrigate(summary: PlantingSummary | null): number | null {
  if (!summaryActive(summary)) return null
  if (summary!.status === 'irrigate') return 0
  return summary!.crossing?.days ?? null
}

/** A field's most urgent planting, which places the field among the others; null without one */
export function primary(card: FieldCard): PlantingSummary | null {
  const soonest = (summary: PlantingSummary) => summaryDaysToIrrigate(summary) ?? Infinity
  return card.plantings.toSorted((a, b) => summaryUrgency(a) - summaryUrgency(b) || soonest(a) - soonest(b))[0] ?? null
}

export const isActive = (card: FieldCard) => summaryActive(primary(card))

/** Where a field stands: its most urgent planting's urgency (summaryUrgency) */
export const urgency = (card: FieldCard): number => summaryUrgency(primary(card))

/** Days until the field's first planting needs water (0 when one does now), or null if none within the forecast */
export const daysToIrrigate = (card: FieldCard): number | null => summaryDaysToIrrigate(primary(card))

/** In season and needing water within the next days (0: today) */
export function needsWaterWithin(card: FieldCard, days: number): boolean {
  const due = daysToIrrigate(card)
  return due !== null && due <= days
}

/** The most urgent status among a pivot's fields in season, or null if none is */
export function pivotStatus(fields: FieldCard[]): Status | null {
  const active = fields.flatMap((card) => card.plantings.filter(summaryActive).map((summary) => summary.status!))
  return STATUSES.find((status) => active.includes(status)) ?? null
}

export type ListItem = {
  card: FieldCard
  pivot: { id: number; name: string; kind_name: string; latitude: number; weather_updating: boolean }
  farm: { id: number; name: string }
}

export type SortOrder = 'urgent' | 'north'

const byName = (a: ListItem, b: ListItem) =>
  a.pivot.name.localeCompare(b.pivot.name) || a.card.name.localeCompare(b.card.name)

/**
 * Most urgent: by urgency, then soonest to need water (no projected date last), then by name.
 * North to south: by pivot latitude (the order they appear on the map), a pivot's fields together.
 */
export function sortItems(items: ListItem[], order: SortOrder): ListItem[] {
  if (order === 'north') {
    return items.toSorted((a, b) => b.pivot.latitude - a.pivot.latitude || a.pivot.id - b.pivot.id || byName(a, b))
  }
  const soonest = (item: ListItem) => daysToIrrigate(item.card) ?? Infinity
  return items.toSorted((a, b) => urgency(a.card) - urgency(b.card) || soonest(a) - soonest(b) || byName(a, b))
}
