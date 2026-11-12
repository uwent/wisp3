import { describe, expect, it } from 'vitest'

import type { PlantingSummary } from '@/types/serializers'

import {
  buildTree,
  daysToIrrigate,
  type FarmGroup,
  type FarmNode,
  type FieldCard,
  type GroupNode,
  needsWaterWithin,
  type PivotGroup,
  pivotStatus,
  type SystemNode,
  treeFields,
  urgency,
} from './overview'

const summary = (overrides: Partial<PlantingSummary>) =>
  ({ phase: 'active', status: 'ok', weather_pending: false, crossing: null, ...overrides }) as PlantingSummary

const card = (name: string, overrides: Partial<PlantingSummary> | null = {}): FieldCard => ({
  id: name.length,
  name,
  plantings: overrides ? [summary(overrides)] : [],
})

const crossing = (days: number) => ({ date: '2026-07-20', days, ad: 0, refill: 1 })

describe('urgency', () => {
  it('puts statuses in season first, then upcoming, ended and no crop', () => {
    const cards = [
      card('none', null),
      card('ended', { phase: 'ended' }),
      card('upcoming', { phase: 'upcoming', status: null }),
      card('pending', { weather_pending: true }),
      card('full', { status: 'full' }),
      card('ok'),
      card('caution', { status: 'caution' }),
      card('irrigate', { status: 'irrigate' }),
      card('no canopy', { status: 'needs_canopy' }),
    ]
    expect(cards.toSorted((a, b) => urgency(a) - urgency(b)).map((c) => c.name)).toEqual([
      'irrigate',
      'caution',
      'no canopy',
      'ok',
      'full',
      'pending',
      'upcoming',
      'ended',
      'none',
    ])
  })
})

describe('needing water', () => {
  it('counts a field at the irrigation point as now, and others by the projected crossing', () => {
    expect(daysToIrrigate(card('dry', { status: 'irrigate' }))).toBe(0)
    expect(daysToIrrigate(card('soon', { status: 'caution', crossing: crossing(2) }))).toBe(2)
    expect(daysToIrrigate(card('wet'))).toBeNull()
    expect(daysToIrrigate(card('ended', { phase: 'ended', crossing: crossing(1) }))).toBeNull()
  })

  it('picks the fields within the window', () => {
    const soon = card('soon', { status: 'caution', crossing: crossing(3) })
    expect(needsWaterWithin(soon, 3)).toBe(true)
    expect(needsWaterWithin(soon, 0)).toBe(false)
    expect(needsWaterWithin(card('wet'), 7)).toBe(false)
  })
})

describe('pivotStatus', () => {
  it("is the most urgent status among the pivot's fields in season", () => {
    expect(
      pivotStatus([card('a'), card('b', { status: 'caution' }), card('c', { phase: 'ended', status: 'irrigate' })]),
    ).toBe('caution')
    expect(pivotStatus([card('a', { phase: 'ended' }), card('b', null)])).toBeNull()
    expect(pivotStatus([])).toBeNull()
  })
})

describe('buildTree', () => {
  type P = PivotGroup & { latitude: number }
  let nextId = 100
  const pivot = (name: string, latitude: number, fields: FieldCard[], group: number | null = null): P => ({
    id: nextId++,
    name,
    kind_name: 'Pivot',
    pivot_group_id: group,
    weather_updating: false,
    latitude,
    fields,
  })
  const field = (name: string, overrides: Partial<PlantingSummary> | null = {}): FieldCard => ({
    ...card(name, overrides),
    id: nextId++,
  })
  // Coloma: South (in the East half group) and North; Hancock: Middle and an empty pivot
  const farms: FarmGroup<P>[] = [
    {
      id: 1,
      name: 'Coloma',
      pivot_groups: [{ id: 7, name: 'East half' }],
      pivots: [
        pivot('South', 44.0, [field('B ok'), field('E dry', { status: 'irrigate' })], 7),
        pivot('North', 44.5, [
          field('A later', { status: 'caution', crossing: crossing(3) }),
          field('D ended', { phase: 'ended' }),
        ]),
      ],
    },
    {
      id: 2,
      name: 'Hancock',
      pivot_groups: [],
      pivots: [
        pivot('Middle', 44.2, [field('C sooner', { status: 'caution', crossing: crossing(1) })]),
        pivot('Empty', 44.3, []),
      ],
    },
  ]
  // The tree as names, indented by level
  const outline = (tree: FarmNode<P>[]) => {
    const system = (node: SystemNode<P>, indent: string) => [
      `${indent}${node.pivot.name}`,
      ...node.fields.map((card) => `${indent}  ${card.name}`),
    ]
    return tree.flatMap((farm) => [
      farm.name,
      ...farm.children.flatMap((child: GroupNode<P> | SystemNode<P>) =>
        child.kind === 'group'
          ? [`  ${child.name}`, ...child.systems.flatMap((node) => system(node, '    '))]
          : system(child, '  '),
      ),
    ])
  }

  it('orders each level by its most urgent field, soonest to need water next', () => {
    expect(outline(buildTree(farms, { order: 'urgent' }))).toEqual([
      'Coloma',
      '  East half',
      '    South',
      '      E dry',
      '      B ok',
      '  North',
      '    A later',
      '    D ended',
      'Hancock',
      '  Middle',
      '    C sooner',
      '  Empty',
    ])
  })

  it('orders north to south, a parent by its northernmost system', () => {
    expect(outline(buildTree(farms, { order: 'north' }))).toEqual([
      'Coloma',
      '  North',
      '    A later',
      '    D ended',
      '  East half',
      '    South',
      '      B ok',
      '      E dry',
      'Hancock',
      '  Empty',
      '  Middle',
      '    C sooner',
    ])
  })

  it('keeps what matches the filter with its parents, and everything under a match', () => {
    expect(outline(buildTree(farms, { order: 'urgent', query: 'dry' }))).toEqual([
      'Coloma',
      '  East half',
      '    South',
      '      E dry',
    ])
    expect(outline(buildTree(farms, { order: 'urgent', query: 'east HALF' }))).toEqual([
      'Coloma',
      '  East half',
      '    South',
      '      E dry',
      '      B ok',
    ])
    // A system matched by name stays without fields
    expect(outline(buildTree(farms, { order: 'urgent', query: 'empty' }))).toEqual(['Hancock', '  Empty'])
    expect(buildTree(farms, { order: 'urgent', query: 'nothing' })).toEqual([])
  })

  it('keeps the fields needing water within the window, and the parents left with any', () => {
    expect(outline(buildTree(farms, { order: 'urgent', windowDays: 1 }))).toEqual([
      'Coloma',
      '  East half',
      '    South',
      '      E dry',
      'Hancock',
      '  Middle',
      '    C sooner',
    ])
    expect(treeFields(buildTree(farms, { order: 'urgent', windowDays: 0 })).map((c) => c.name)).toEqual(['E dry'])
  })
})
