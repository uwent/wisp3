import { type Boundary, boundaryCenter } from '@/lib/boundary'

// Setup's order (Ben, 2026-11-17): north to south (the default), each level by its northernmost
// point (a field by its shape's center, or its system's location without one; a group or farm by
// its northernmost system), or by name. Names compare as people read them ("K2" before "K10"), and
// break ties. A farm's irrigation groups and its systems in none are listed together.

export type SetupOrder = 'north' | 'name'
export const SETUP_ORDERS: { value: SetupOrder; label: string }[] = [
  { value: 'north', label: 'North to south' },
  { value: 'name', label: 'By name' },
]

type OrderField = { name: string; boundary: Boundary | null }
type OrderPivot = { name: string; latitude: number; pivot_group_id: number | null; fields: OrderField[] }
type OrderGroup = { id: number; name: string }
type OrderFarm = { name: string; pivots: OrderPivot[]; pivot_groups: OrderGroup[] }

export type SetupChild<P, G> = { kind: 'group'; group: G; pivots: P[] } | { kind: 'system'; pivot: P }

const byName = (a: { name: string }, b: { name: string }) =>
  a.name.localeCompare(b.name, undefined, { numeric: true, sensitivity: 'base' })

function sorted<T extends { name: string }>(items: T[], order: SetupOrder, north: (item: T) => number): T[] {
  if (order === 'name') return items.toSorted(byName)
  return items
    .map((item) => ({ item, north: north(item) }))
    .toSorted((a, b) => b.north - a.north || byName(a.item, b.item))
    .map(({ item }) => item)
}

/** A system's fields in order */
export function orderFields<F extends OrderField>(pivot: { latitude: number; fields: F[] }, order: SetupOrder): F[] {
  return sorted(pivot.fields, order, (field) => (field.boundary ? boundaryCenter(field.boundary)[1] : pivot.latitude))
}

const pivotNorth = (pivot: OrderPivot) =>
  Math.max(
    pivot.latitude,
    ...pivot.fields.flatMap((field) => (field.boundary ? [boundaryCenter(field.boundary)[1]] : [])),
  )

/** A farm's irrigation groups (with their systems) and its systems in none, in order */
export function farmChildren<P extends OrderPivot, G extends OrderGroup>(
  farm: { pivots: P[]; pivot_groups: G[] },
  order: SetupOrder,
): SetupChild<P, G>[] {
  const groups = farm.pivot_groups.map((group) => ({
    kind: 'group' as const,
    group,
    name: group.name,
    pivots: sorted(
      farm.pivots.filter((pivot) => pivot.pivot_group_id === group.id),
      order,
      pivotNorth,
    ),
  }))
  const grouped = new Set(groups.flatMap((child) => child.pivots))
  const systems = farm.pivots
    .filter((pivot) => !grouped.has(pivot))
    .map((pivot) => ({ kind: 'system' as const, pivot, name: pivot.name }))
  return sorted<(typeof groups)[number] | (typeof systems)[number]>([...groups, ...systems], order, (child) =>
    child.kind === 'group' ? Math.max(...child.pivots.map(pivotNorth), -Infinity) : pivotNorth(child.pivot),
  ).map((child) =>
    child.kind === 'group'
      ? { kind: 'group', group: child.group, pivots: child.pivots }
      : { kind: 'system', pivot: child.pivot },
  )
}

/** The farms in order */
export function orderFarms<F extends OrderFarm>(farms: F[], order: SetupOrder): F[] {
  return sorted(farms, order, (farm) => Math.max(...farm.pivots.map(pivotNorth), -Infinity))
}
