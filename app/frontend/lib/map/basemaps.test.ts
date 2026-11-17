import type { StyleSpecification } from 'maplibre-gl'
import { describe, expect, it } from 'vitest'

import { basemapStyle, IMAGERY_ROADS, repairStyle } from './basemaps'
import { ROAD_LAYER_PREFIX } from './roads.svelte'

describe('repairStyle', () => {
  it("gives a road without a number a long ref_length, so the shield filters don't warn", () => {
    const style = {
      version: 8,
      sources: {},
      layers: [
        {
          id: 'road_shield_us',
          type: 'symbol',
          source: 'openmaptiles',
          filter: ['all', ['<=', ['get', 'ref_length'], 6], ['match', ['get', 'network'], ['us-state'], true, false]],
        },
        { id: 'background', type: 'background' },
      ],
    } as StyleSpecification
    const [shield, background] = repairStyle(style).layers
    expect('filter' in shield && shield.filter).toEqual([
      'all',
      ['<=', ['coalesce', ['get', 'ref_length'], 1000], 6],
      ['match', ['get', 'network'], ['us-state'], true, false],
    ])
    expect(background).toBe(style.layers[1])
  })
})

describe('IMAGERY_ROADS', () => {
  it('draws from OpenFreeMap tiles under unique ids', () => {
    const ids = IMAGERY_ROADS.map((layer) => layer.id)
    expect(new Set(ids).size).toBe(ids.length)
    expect(IMAGERY_ROADS.every((layer) => 'source' in layer && layer.source === 'openmaptiles')).toBe(true)
    expect(ids.every((id) => id.startsWith(ROAD_LAYER_PREFIX))).toBe(true)
  })

  it('starts hidden when roads are switched off', () => {
    const style = basemapStyle('imagery', false) as { layers: { id: string; layout?: { visibility?: string } }[] }
    expect(style.layers.find((layer) => layer.id === 'imagery')?.layout?.visibility).toBeUndefined()
    expect(style.layers.filter((layer) => layer.layout?.visibility === 'none')).toHaveLength(IMAGERY_ROADS.length)
  })
})
