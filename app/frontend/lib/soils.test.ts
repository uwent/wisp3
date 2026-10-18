import { describe, expect, it } from 'vitest'

import { pivotRing } from './geo'
import { parseSoilAreas, parseSoilTable, soilAreaQuery, soilKeyFor, soilQuery, suggestSoil, wktPolygons } from './soils'

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

describe('soil types around a pivot', () => {
  it('reads polygons from WKT, leaving out lines and points', () => {
    expect(wktPolygons('POLYGON ((0 0, 1 0, 1 1, 0 0))')).toEqual([
      [
        [
          [0, 0],
          [1, 0],
          [1, 1],
          [0, 0],
        ],
      ],
    ])
    const multi = wktPolygons(
      'MULTIPOLYGON (((0 0, 1 0, 1 1, 0 0)), ((5 5, 6 5, 6 6, 5 5), (5.1 5.1, 5.2 5.1, 5.2 5.2, 5.1 5.1)))',
    )
    expect(multi).toHaveLength(2)
    expect(multi[1]).toHaveLength(2)
    const collection = wktPolygons(
      'GEOMETRYCOLLECTION (POLYGON ((0 0, 1 0, 1 1, 0 0)), LINESTRING (0 0, 2 2), POINT (3 3), POLYGON EMPTY)',
    )
    expect(collection).toHaveLength(1)
    expect(wktPolygons('POLYGON ((-89.5 44.1, -89.4 44.1, -89.4 44.2, -89.5 44.1))')[0][0][1]).toEqual([-89.4, 44.1])
  })

  it("turns the survey's table into soil type areas", () => {
    const areas = parseSoilAreas({
      Table: [
        ['mukey', 'wkt', 'muname', 'texdesc'],
        ['1', 'POLYGON ((0 0, 1 0, 1 1, 0 0))', 'Coloma loamy sand, 6 to 12 percent slopes', 'Loamy sand'],
        ['2', 'LINESTRING (0 0, 1 1)', 'Plainfield sand', 'Sand'],
        ['3', 'POLYGON ((0 0, 1 0, 1 1, 0 0))', 'Water', null],
      ],
    })
    expect(areas.features.map((f) => f.properties)).toEqual([
      { key: 'loamy_sand', unit: 'Coloma loamy sand, 6 to 12 percent slopes', texture: 'Loamy sand' },
      { key: null, unit: 'Water', texture: null },
    ])
  })

  it('asks for the map units in the area, simplified', () => {
    const query = soilAreaQuery([-89.55, 44.11, -89.49, 44.15])
    expect(query).toContain('POLYGON((-89.550000 44.110000, -89.490000 44.110000')
    expect(query).toContain('STAsText()')
  })
})
