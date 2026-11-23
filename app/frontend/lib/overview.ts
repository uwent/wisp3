import type { PlantingSummary } from '@/types/serializers'

import { fieldMatches, searchText } from './search'

// The operation's farms, pivots and field cards (OperationOverview), as the dashboard and the map
// get them, and how the map orders and picks them

/**
 * A field and its plantings in season today, or the nearest this year (several on a field of plots);
 * empty without a planting this year
 */
export type FieldCard = { id: number; name: string; plantings: PlantingSummary[] }
/** An irrigation system with its field cards. weather_updating: a weather update for its cell is queued or running */
export type OverviewSystem = {
  id: number
  name: string
  /** "Pivot", "Traveler" (Pivot::KIND_NAMES) */
  kind_name: string
  /** Its irrigation group (PivotGroup), if any */
  pivot_group_id: number | null
  weather_updating: boolean
  fields: FieldCard[]
}
export type FarmGroup<P extends OverviewSystem = OverviewSystem> = {
  id: number
  name: string
  /** Its irrigation groups */
  pivot_groups: { id: number; name: string }[]
  pivots: P[]
}

export type Status = NonNullable<PlantingSummary['status']>

/** Most urgent first: irrigated crops by what they need, then rainfed ones by their stress (FieldStatuses::RANK) */
export const STATUSES: Status[] = [
  'irrigate',
  'caution',
  'needs_canopy',
  'ok',
  'full',
  'stressed',
  'stress_coming',
  'no_stress',
]

/** The pivots whose weather is being updated, so the page waits for it to land (lib/poll.ts) */
export const updatingIds = (farms: FarmGroup[]) =>
  farms.flatMap((farm) => farm.pivots.filter((pivot) => pivot.weather_updating).map((pivot) => pivot.id))

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

/** Days until the planting needs water (0 when it does now), or null if not within the forecast or rainfed */
function summaryDaysToIrrigate(summary: PlantingSummary | null): number | null {
  if (!summaryActive(summary) || summary!.rainfed) return null
  if (summary!.status === 'irrigate') return 0
  return summary!.crossing?.days ?? null
}

/** A field's most urgent planting, which places the field among the others; null without one */
export function primary(card: FieldCard): PlantingSummary | null {
  const soonest = (summary: PlantingSummary) => summaryDaysToIrrigate(summary) ?? Infinity
  return card.plantings.toSorted((a, b) => summaryUrgency(a) - summaryUrgency(b) || soonest(a) - soonest(b))[0] ?? null
}

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

export type SortOrder = 'urgent' | 'north'

// The map's list: the operation as a tree of cards, farm › irrigation group
// › system › field, as on the dashboard and Setup (a system in no group sits under its farm).

/** What's selected on the map page: one card in the list, and its system or field on the map */
export type Selection = { level: 'farm' | 'group' | 'system' | 'field' | 'zone'; id: number }

export type SystemNode<P> = { kind: 'system'; pivot: P; fields: FieldCard[] }
export type GroupNode<P> = { kind: 'group'; id: number; name: string; systems: SystemNode<P>[] }
export type FarmNode<P> = { kind: 'farm'; id: number; name: string; children: (GroupNode<P> | SystemNode<P>)[] }

export type TreeOptions = {
  order: SortOrder
  /** Text to match in a field's, system's, group's or farm's name, or a field's crops (lib/search.ts); a match keeps its parents, and everything under it */
  query?: string
  /** Only fields needing water within these days (0: today), and the parents left with any; null for all */
  windowDays?: number | null
  /** Only fields with a planting growing today (the map's Growing now), and the parents left with any */
  growing?: boolean
}

// Where a card sorts: its most urgent field's urgency and days to water, its northernmost
// system, and its name
type SortKey = { urgency: number; soonest: number; north: number; name: string }

const fieldKey = (card: FieldCard, latitude: number): SortKey => ({
  urgency: urgency(card),
  soonest: daysToIrrigate(card) ?? Infinity,
  north: latitude,
  name: card.name,
})

function compare(a: SortKey, b: SortKey, order: SortOrder): number {
  const byName = a.name.localeCompare(b.name)
  if (order === 'north') return b.north - a.north || byName
  return a.urgency - b.urgency || a.soonest - b.soonest || b.north - a.north || byName
}

/** A parent's key from its children's: the most urgent of them, and the northernmost */
function parentKey(children: SortKey[], name: string, north?: number): SortKey {
  const first = children.toSorted((a, b) => compare(a, b, 'urgent'))[0]
  return {
    urgency: first?.urgency ?? Infinity,
    soonest: first?.soonest ?? Infinity,
    north: north ?? Math.max(...children.map((key) => key.north), -Infinity),
    name,
  }
}

function sortByKey<T>(items: T[], key: (item: T) => SortKey, order: SortOrder): T[] {
  const keyed = items.map((item) => ({ item, key: key(item) }))
  return keyed.toSorted((a, b) => compare(a.key, b.key, order)).map(({ item }) => item)
}

/**
 * The list's tree: each level ordered by its most urgent field ("Most urgent first", soonest to
 * need water next, then north to south) or by latitude ("North to south", a parent by its
 * northernmost system), names breaking ties. A query keeps what matches with its parents; the window keeps fields needing water
 * within it, and a parent left with none of them goes. Without either, systems without fields are
 * listed too, to select them.
 */
export function buildTree<P extends OverviewSystem & { latitude: number }>(
  farms: FarmGroup<P>[],
  { order, query = '', windowDays = null, growing = false }: TreeOptions,
): FarmNode<P>[] {
  const text = searchText(query)
  const matches = (name: string) => !text || name.toLowerCase().includes(text)
  const filtering = text !== '' || windowDays !== null || growing

  const systemKey = (node: SystemNode<P>) =>
    parentKey(
      node.fields.map((card) => fieldKey(card, node.pivot.latitude)),
      node.pivot.name,
      node.pivot.latitude,
    )
  const keyOf = (node: GroupNode<P> | SystemNode<P>): SortKey =>
    node.kind === 'system' ? systemKey(node) : parentKey(node.systems.map(systemKey), node.name)

  const system = (pivot: P, matched: boolean): SystemNode<P> | null => {
    const within = matched || matches(pivot.name)
    const fields = pivot.fields.filter(
      (card) =>
        (within || fieldMatches(card, text)) &&
        (windowDays === null || needsWaterWithin(card, windowDays)) &&
        (!growing || card.plantings.some((summary) => summary.phase === 'active')),
    )
    if (filtering && !fields.length && !(within && windowDays === null && !growing)) return null
    const sorted = sortByKey(fields, (card) => fieldKey(card, pivot.latitude), order)
    return { kind: 'system', pivot, fields: sorted }
  }

  const tree = farms.flatMap((farm): FarmNode<P>[] => {
    const farmMatched = matches(farm.name) && text !== ''
    const groups = farm.pivot_groups.flatMap((group): GroupNode<P>[] => {
      const matched = farmMatched || (text !== '' && matches(group.name))
      const systems = farm.pivots
        .filter((pivot) => pivot.pivot_group_id === group.id)
        .flatMap((pivot) => system(pivot, matched) ?? [])
      if (!systems.length) return []
      return [{ kind: 'group', id: group.id, name: group.name, systems: sortByKey(systems, systemKey, order) }]
    })
    const ungrouped = farm.pivots
      .filter((pivot) => pivot.pivot_group_id === null || !farm.pivot_groups.some((g) => g.id === pivot.pivot_group_id))
      .flatMap((pivot) => system(pivot, farmMatched) ?? [])
    const children = sortByKey<GroupNode<P> | SystemNode<P>>([...groups, ...ungrouped], keyOf, order)
    if (!children.length && filtering) return []
    return [{ kind: 'farm', id: farm.id, name: farm.name, children }]
  })
  return sortByKey(tree, (farm) => parentKey(farm.children.map(keyOf), farm.name), order)
}

/** The systems under a node of the tree */
export const treeSystems = <P>(node: FarmNode<P> | GroupNode<P> | SystemNode<P>): SystemNode<P>[] =>
  node.kind === 'system' ? [node] : node.kind === 'group' ? node.systems : node.children.flatMap(treeSystems)

/** The fields listed in the tree */
export const treeFields = <P>(tree: FarmNode<P>[]): FieldCard[] =>
  tree.flatMap(treeSystems).flatMap((node) => node.fields)

// The dashboard's choices: its fields by farm and system or most urgent first, and a
// status count clicked to show only the fields at that status

/** A status count to filter by: a status in season, or the season ended */
export type StatusFilter = Status | 'ended'

/** Whether a field stands at the status, as StatusCounts counts it (its most urgent planting's) */
export function matchesStatus(card: FieldCard, filter: StatusFilter | null): boolean {
  if (filter === null) return true
  const summary = primary(card)
  if (filter === 'ended') return summary?.phase === 'ended'
  return summary?.phase === 'active' && summary.status === filter
}

/** The farms with only the fields at the status, and the systems and farms left with any; all of them without a filter */
export function filterByStatus<P extends OverviewSystem>(farms: FarmGroup<P>[], filter: StatusFilter | null) {
  if (filter === null) return farms
  return farms.flatMap((farm) => {
    const pivots = farm.pivots.flatMap((pivot) => {
      const fields = pivot.fields.filter((card) => matchesStatus(card, filter))
      return fields.length ? [{ ...pivot, fields }] : []
    })
    return pivots.length ? [{ ...farm, pivots }] : []
  })
}

/** A field with the system and farm it's under */
export type PlacedField<P extends OverviewSystem = OverviewSystem> = { card: FieldCard; pivot: P; farm: FarmGroup<P> }

/**
 * "Needs water first": every field across farms and systems, most urgent first (urgency, then the
 * soonest to need water), seasons ended and fields with no crop last; ties keep the farms' order
 */
export function needsWaterFirst<P extends OverviewSystem>(farms: FarmGroup<P>[]): PlacedField<P>[] {
  const placed = farms.flatMap((farm) =>
    farm.pivots.flatMap((pivot) => pivot.fields.map((card) => ({ card, pivot, farm }))),
  )
  const keyed = placed.map((item) => ({
    item,
    urgency: urgency(item.card),
    soonest: daysToIrrigate(item.card) ?? Infinity,
  }))
  return keyed.toSorted((a, b) => a.urgency - b.urgency || a.soonest - b.soonest).map(({ item }) => item)
}
