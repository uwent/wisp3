import { describe, expect, it } from 'vitest'

import type { Boundary } from '@/lib/boundary'

import { farmChildren, orderFarms, orderFields } from './order'

const square = (lat: number): Boundary => ({
  type: 'Polygon',
  coordinates: [
    [
      [-89.5, lat],
      [-89.49, lat],
      [-89.49, lat + 0.01],
      [-89.5, lat],
    ],
  ],
})

describe('Setup order', () => {
  const field = (name: string, lat: number | null) => ({ name, boundary: lat === null ? null : square(lat) })
  const pivot = (
    name: string,
    latitude: number,
    group: number | null = null,
    fields = [field(`${name} field`, null)],
  ) => ({
    name,
    latitude,
    pivot_group_id: group,
    fields,
  })

  it('orders fields by their shapes, those without one at their system, or by name as read', () => {
    const fields = [field('K10', 44.0), field('K2', 44.2), field('K1', null)]
    expect(orderFields({ latitude: 44.1, fields }, 'north').map((f) => f.name)).toEqual(['K2', 'K1', 'K10'])
    expect(orderFields({ latitude: 44.1, fields }, 'name').map((f) => f.name)).toEqual(['K1', 'K2', 'K10'])
  })

  it("lists a farm's groups among its other systems, a group at its northernmost", () => {
    const farm = {
      pivots: [pivot('South', 43.9), pivot('A', 44.0, 1), pivot('B', 44.3, 1), pivot('Middle', 44.1)],
      pivot_groups: [{ id: 1, name: 'Gauge' }],
    }
    const names = (order: 'north' | 'name') =>
      farmChildren(farm, order).map((child) =>
        child.kind === 'group'
          ? `${child.group.name}: ${child.pivots.map((p) => p.name).join(', ')}`
          : child.pivot.name,
      )
    expect(names('north')).toEqual(['Gauge: B, A', 'Middle', 'South'])
    expect(names('name')).toEqual(['Gauge: A, B', 'Middle', 'South'])
  })

  it('orders farms by their northernmost system, a field shape counting', () => {
    const farms = [
      { name: 'Arlington', pivots: [pivot('North', 43.3)], pivot_groups: [] },
      { name: 'Coloma', pivots: [pivot('Shop', 44.0, null, [field('Far north', 44.5)])], pivot_groups: [] },
      { name: 'Empty', pivots: [], pivot_groups: [] },
    ]
    expect(orderFarms(farms, 'north').map((f) => f.name)).toEqual(['Coloma', 'Arlington', 'Empty'])
    expect(orderFarms(farms, 'name').map((f) => f.name)).toEqual(['Arlington', 'Coloma', 'Empty'])
  })
})
