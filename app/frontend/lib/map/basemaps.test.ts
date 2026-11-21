import type { Map as MapLibreMap, StyleSpecification } from 'maplibre-gl'
import { describe, expect, it, vi } from 'vitest'

import { type Basemap, BasemapSwitch, basemapStyle, IMAGERY_ROADS, repairStyle } from './basemaps'
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

describe('BasemapSwitch', () => {
  // A map whose next style loads, or never does (its service is down)
  const fakeMap = () => {
    const state = { loads: true, styles: 0 }
    const map = {
      once: (_event: string, callback: () => void) => state.loads && queueMicrotask(callback),
      setStyle: () => state.styles++,
    } as unknown as MapLibreMap
    return { map, state }
  }

  it('shows the choice at once, and runs after once the style is in place', async () => {
    const { map, state } = fakeMap()
    const shown: Basemap[] = []
    const after = vi.fn()
    const toggle = new BasemapSwitch('imagery', {
      map: () => map,
      isOwn: () => false,
      show: (b) => shown.push(b),
      after,
    })
    expect(await toggle.change('streets')).toBe(true)
    expect([shown, state.styles, after.mock.calls.length]).toEqual([['streets'], 1, 1])
    expect(await toggle.change('streets')).toBe(false)
    expect(state.styles).toBe(1)
  })

  it('puts the toggle back when the style fails to load, so the same button retries', async () => {
    vi.useFakeTimers()
    try {
      const { map, state } = fakeMap()
      const shown: Basemap[] = []
      const after = vi.fn()
      const toggle = new BasemapSwitch('imagery', {
        map: () => map,
        isOwn: () => false,
        show: (b) => shown.push(b),
        after,
      })
      state.loads = false
      const failed = toggle.change('streets')
      await vi.runAllTimersAsync()
      expect(await failed).toBe(false)
      expect(shown).toEqual(['streets', 'imagery'])
      expect(after).not.toHaveBeenCalled()
      state.loads = true
      expect(await toggle.change('streets')).toBe(true)
      expect([shown.at(-1), state.styles, after.mock.calls.length]).toEqual(['streets', 2, 1])
    } finally {
      vi.useRealTimers()
    }
  })
})
