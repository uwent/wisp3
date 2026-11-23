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
type OrderSystem = { name: string; latitude: number; irrigation_group_id: number | null; fields: OrderField[] }
type OrderGroup = { id: number; name: string }
type OrderFarm = { name: string; systems: OrderSystem[]; irrigation_groups: OrderGroup[] }

export type SetupChild<P, G> = { kind: 'group'; group: G; systems: P[] } | { kind: 'system'; system: P }

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
export function orderFields<F extends OrderField>(system: { latitude: number; fields: F[] }, order: SetupOrder): F[] {
  return sorted(system.fields, order, (field) => (field.boundary ? boundaryCenter(field.boundary)[1] : system.latitude))
}

const systemNorth = (system: OrderSystem) =>
  Math.max(
    system.latitude,
    ...system.fields.flatMap((field) => (field.boundary ? [boundaryCenter(field.boundary)[1]] : [])),
  )

/** A farm's irrigation groups (with their systems) and its systems in none, in order */
export function farmChildren<P extends OrderSystem, G extends OrderGroup>(
  farm: { systems: P[]; irrigation_groups: G[] },
  order: SetupOrder,
): SetupChild<P, G>[] {
  const groups = farm.irrigation_groups.map((group) => ({
    kind: 'group' as const,
    group,
    name: group.name,
    systems: sorted(
      farm.systems.filter((system) => system.irrigation_group_id === group.id),
      order,
      systemNorth,
    ),
  }))
  const grouped = new Set(groups.flatMap((child) => child.systems))
  const systems = farm.systems
    .filter((system) => !grouped.has(system))
    .map((system) => ({ kind: 'system' as const, system, name: system.name }))
  return sorted<(typeof groups)[number] | (typeof systems)[number]>([...groups, ...systems], order, (child) =>
    child.kind === 'group' ? Math.max(...child.systems.map(systemNorth), -Infinity) : systemNorth(child.system),
  ).map((child) =>
    child.kind === 'group'
      ? { kind: 'group', group: child.group, systems: child.systems }
      : { kind: 'system', system: child.system },
  )
}

/** The farms in order */
export function orderFarms<F extends OrderFarm>(farms: F[], order: SetupOrder): F[] {
  return sorted(farms, order, (farm) => Math.max(...farm.systems.map(systemNorth), -Infinity))
}
