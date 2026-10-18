import type { PlantingSummary } from '@/types/serializers'

// The operation's farms, pivots and field cards (OperationOverview), as the dashboard and the map
// get them, and how the map orders and picks them

export type FieldCard = { id: number; name: string; summary: PlantingSummary | null }
export type PivotGroup = { id: number; name: string; fields: FieldCard[] }
export type FarmGroup<P extends PivotGroup = PivotGroup> = { id: number; name: string; pivots: P[] }

export type Status = NonNullable<PlantingSummary['status']>

/** Most urgent first */
export const STATUSES: Status[] = ['irrigate', 'caution', 'ok', 'full']

/** In season, with a status (not upcoming, ended, without a crop, or waiting for weather) */
export const isActive = (card: FieldCard) =>
  card.summary?.phase === 'active' && !card.summary.weather_pending && card.summary.status !== null

/**
 * Where a field stands, most urgent first: in season by status (irrigate, caution, ok, full), in
 * season without one yet, then upcoming, season ended, and no crop
 */
export function urgency(card: FieldCard): number {
  const summary = card.summary
  if (!summary) return 7
  if (summary.phase === 'upcoming') return 5
  if (summary.phase === 'ended') return 6
  return isActive(card) ? STATUSES.indexOf(summary.status!) : 4
}

/** Days until the field needs water (0 when it does now), or null if not within the forecast */
export function daysToIrrigate(card: FieldCard): number | null {
  if (!isActive(card)) return null
  if (card.summary!.status === 'irrigate') return 0
  return card.summary!.crossing?.days ?? null
}

/** In season and needing water within the next days (0: today) */
export function needsWaterWithin(card: FieldCard, days: number): boolean {
  const due = daysToIrrigate(card)
  return due !== null && due <= days
}

/** The most urgent status among a pivot's fields in season, or null if none is */
export function pivotStatus(fields: FieldCard[]): Status | null {
  const active = fields.filter(isActive).map((card) => card.summary!.status!)
  return STATUSES.find((status) => active.includes(status)) ?? null
}

export type ListItem = {
  card: FieldCard
  pivot: { id: number; name: string; latitude: number }
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
