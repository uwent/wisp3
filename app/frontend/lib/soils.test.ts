import { describe, expect, it } from 'vitest'

import { pivotRing } from './geo'
import { parseSoilTable, soilKeyFor, soilQuery, suggestSoil } from './soils'

// Soil Data Access's answer for the demo's North 160 pivot (44.1335, −89.5213, 1300 ft), 2026-10-17
const NORTH_160 = {
  Table: [
    ['mukey', 'share', 'muname', 'compname', 'comppct_r', 'texdesc'],
    ['423976', '0.494257828744363', 'Plainfield sand, 2 to 6 percent slopes', 'Plainfield', '90', 'Sand'],
    ['423954', '0.378912743039554', 'Coloma loamy sand, 6 to 12 percent slopes', 'Coloma', '85', 'Loamy sand'],
    [
      '423978',
      '0.0349360388192718',
      'Plainfield sand, till plain, 12 to 30 percent slopes',
      'Plainfield',
      '90',
      'Sand',
    ],
    ['3182176', '0.0280573103224188', 'Markey muck, acid, lake plain, 0 to 1 percent slopes', 'Markey', '95', 'Muck'],
    ['423992', '0.0194119506064234', 'Water', 'Water', '100', null],
    ['423984', '0.0184796661770826', 'Richford loamy sand, 2 to 6 percent slopes', 'Richford', '92', 'Loamy sand'],
    ['423953', '0.0147783050724868', 'Coloma loamy sand, 2 to 6 percent slopes', 'Coloma', '85', 'Loamy sand'],
    ['423975', '0.00702062932767675', 'Plainfield sand, 0 to 2 percent slopes', 'Plainfield', '90', 'Sand'],
    [
      '3008214',
      '0.0041455278907226',
      'Newson mucky loamy sand, 0 to 1 percent slopes',
      'Newson',
      '90',
      'Highly decomposed plant material',
    ],
  ],
}

describe('soilKeyFor', () => {
  it("matches USDA textures to WISP's soil types, dropping modifiers", () => {
    expect(soilKeyFor('Sand')).toBe('sand')
    expect(soilKeyFor('Fine sand')).toBe('sand')
    expect(soilKeyFor('Loamy fine sand')).toBe('loamy_sand')
    expect(soilKeyFor('Very fine sandy loam')).toBe('sandy_loam')
    expect(soilKeyFor('Gravelly silt loam')).toBe('silt_loam')
    expect(soilKeyFor('Mucky peat')).toBe('muck')
    expect(soilKeyFor('Highly decomposed plant material')).toBe('muck')
    expect(soilKeyFor('Silty clay')).toBeNull()
    expect(soilKeyFor('Peat')).toBeNull()
    expect(soilKeyFor(null)).toBeNull()
  })
})

describe('the soil survey under a pivot', () => {
  it('asks for the map units under the polygon, with their shares and surface textures', () => {
    const query = soilQuery(pivotRing([-89.5213, 44.1335], 1300))
    expect(query).toContain("STGeomFromText('POLYGON((-89.5213")
    expect(query).toContain('mupolygongeo.STIntersection')
    expect(query).toContain('h.hzdept_r = 0')
  })

  it('reads the table and suggests the soil covering the most of the pivot', () => {
    const units = parseSoilTable(NORTH_160)
    expect(units).toHaveLength(9)
    expect(units[0]).toEqual({
      mukey: '423976',
      share: 0.494257828744363,
      name: 'Plainfield sand, 2 to 6 percent slopes',
      component: 'Plainfield',
      texture: 'Sand',
    })
    const suggestion = suggestSoil(units)
    expect(suggestion.key).toBe('sand')
    expect(suggestion.share).toBeCloseTo(0.536, 3)
  })

  it('suggests nothing when little of the pivot matches a soil type', () => {
    const lake = { mukey: '1', share: 0.8, name: 'Water', component: 'Water', texture: null }
    const shore = { mukey: '2', share: 0.2, name: 'Plainfield sand', component: 'Plainfield', texture: 'Sand' }
    expect(suggestSoil([lake, shore]).key).toBeNull()
    expect(suggestSoil([]).key).toBeNull()
  })

  it('reads an empty answer (outside the survey) as no map units', () => {
    expect(parseSoilTable({})).toEqual([])
  })
})
