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
  const system = (
    name: string,
    latitude: number,
    group: number | null = null,
    fields = [field(`${name} field`, null)],
  ) => ({
    name,
    latitude,
    irrigation_group_id: group,
    fields,
  })

  it('orders fields by their shapes, those without one at their system, or by name as read', () => {
    const fields = [field('K10', 44.0), field('K2', 44.2), field('K1', null)]
    expect(orderFields({ latitude: 44.1, fields }, 'north').map((f) => f.name)).toEqual(['K2', 'K1', 'K10'])
    expect(orderFields({ latitude: 44.1, fields }, 'name').map((f) => f.name)).toEqual(['K1', 'K2', 'K10'])
  })

  it("lists a farm's groups among its other systems, a group at its northernmost", () => {
    const farm = {
      systems: [system('South', 43.9), system('A', 44.0, 1), system('B', 44.3, 1), system('Middle', 44.1)],
      irrigation_groups: [{ id: 1, name: 'Gauge' }],
    }
    const names = (order: 'north' | 'name') =>
      farmChildren(farm, order).map((child) =>
        child.kind === 'group'
          ? `${child.group.name}: ${child.systems.map((p) => p.name).join(', ')}`
          : child.system.name,
      )
    expect(names('north')).toEqual(['Gauge: B, A', 'Middle', 'South'])
    expect(names('name')).toEqual(['Gauge: A, B', 'Middle', 'South'])
  })

  it('orders farms by their northernmost system, a field shape counting', () => {
    const farms = [
      { name: 'Arlington', systems: [system('North', 43.3)], irrigation_groups: [] },
      { name: 'Coloma', systems: [system('Shop', 44.0, null, [field('Far north', 44.5)])], irrigation_groups: [] },
      { name: 'Empty', systems: [], irrigation_groups: [] },
    ]
    expect(orderFarms(farms, 'north').map((f) => f.name)).toEqual(['Coloma', 'Arlington', 'Empty'])
    expect(orderFarms(farms, 'name').map((f) => f.name)).toEqual(['Arlington', 'Coloma', 'Empty'])
  })
})
