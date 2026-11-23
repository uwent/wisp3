import { describe, expect, it } from 'vitest'

import { fieldMatches, searchFarms } from './search'

const field = (name: string, ...crops: [string, string | null][]) => ({
  name,
  plantings: crops.map(([plant_name, variety]) => ({ plant_name, variety })),
})
const farms = [
  {
    name: 'Hancock',
    irrigation_groups: [
      { id: 1, name: 'River gauge' },
      { id: 2, name: 'Hill gauge' },
    ],
    systems: [
      { name: 'North system', irrigation_group_id: 1, fields: [field('North 40', ['Potato', 'Russet Burbank'])] },
      { name: 'South pivot', irrigation_group_id: 2, fields: [field('South 80', ['Field Corn', null]), field('Bare')] },
      { name: 'East 9', irrigation_group_id: null, fields: [field('East 9', ['Soybean', 'Double crop'])] },
    ],
  },
  {
    name: 'Coloma',
    irrigation_groups: [],
    systems: [{ name: 'Powell', irrigation_group_id: null, fields: [field('Powell West')] }],
  },
]
const outline = (result: typeof farms) =>
  result.map((farm) => [
    farm.name,
    farm.irrigation_groups.map((group) => group.name),
    farm.systems.map((system) => [system.name, system.fields.map((f) => f.name)]),
  ])

describe('searchFarms', () => {
  it('keeps everything without a query', () => {
    expect(searchFarms(farms, '  ')).toBe(farms)
  })

  it('finds fields by name, crop or variety, in any case, keeping their system and farm', () => {
    expect(outline(searchFarms(farms, 'CORN'))).toEqual([['Hancock', ['Hill gauge'], [['South pivot', ['South 80']]]]])
    expect(outline(searchFarms(farms, 'russet'))).toEqual([
      ['Hancock', ['River gauge'], [['North system', ['North 40']]]],
    ])
    expect(outline(searchFarms(farms, 'west'))).toEqual([['Coloma', [], [['Powell', ['Powell West']]]]])
  })

  it('keeps all of a matching farm, group or system', () => {
    expect(searchFarms(farms, 'coloma')).toEqual([farms[1]])
    expect(outline(searchFarms(farms, 'hill'))).toEqual([
      ['Hancock', ['Hill gauge'], [['South pivot', ['South 80', 'Bare']]]],
    ])
    expect(outline(searchFarms(farms, 'south piv'))).toEqual([
      ['Hancock', ['Hill gauge'], [['South pivot', ['South 80', 'Bare']]]],
    ])
  })

  it('drops what matches nothing', () => {
    expect(searchFarms(farms, 'alfalfa')).toEqual([])
  })

  it("matches only the crops it's given (a season's)", () => {
    expect(searchFarms(farms, 'potato', () => [])).toEqual([])
  })
})

describe('fieldMatches', () => {
  it('matches a field without crops by its name only', () => {
    expect(fieldMatches(field('Bare'), 'bare')).toBe(true)
    expect(fieldMatches(field('Bare'), 'corn')).toBe(false)
  })
})
