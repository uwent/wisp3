import { afterEach, describe, expect, it, vi } from 'vitest'

import { DEFAULT_PREFS, loadPrefs, savePrefs } from './prefs'

afterEach(() => {
  localStorage.clear()
  vi.restoreAllMocks()
})

describe('map prefs', () => {
  it('remembers settings per operation', () => {
    savePrefs(1, { ...DEFAULT_PREFS, basemap: 'streets', overlay: 'drought', listOpen: false })
    expect(loadPrefs(1)).toMatchObject({ basemap: 'streets', overlay: 'drought', listOpen: false })
    expect(loadPrefs(2)).toEqual(DEFAULT_PREFS)
  })

  it('fills in settings saved before they existed, and drops layers the map no longer has', () => {
    localStorage.setItem('wisp-map:1', JSON.stringify({ basemap: 'streets', overlay: 'gone' }))
    expect(loadPrefs(1)).toEqual({ ...DEFAULT_PREFS, basemap: 'streets' })
  })

  it('keeps one overlay of those saved before one at a time, the rain layer first', () => {
    localStorage.setItem('wisp-map:1', JSON.stringify({ rain: 'gone', overlays: ['gone', 'drought'] }))
    expect(loadPrefs(1)).toEqual({ ...DEFAULT_PREFS, overlay: 'drought' })
    localStorage.setItem('wisp-map:1', JSON.stringify({ rain: 'radar', overlays: ['drought'] }))
    expect(loadPrefs(1)).toEqual({ ...DEFAULT_PREFS, overlay: 'radar' })
    localStorage.setItem('wisp-map:1', JSON.stringify({ rain: null, overlays: 'drought' }))
    expect(loadPrefs(1)).toEqual(DEFAULT_PREFS)
  })

  it('starts from the defaults when what was saved is unreadable', () => {
    localStorage.setItem('wisp-map:1', '{not json')
    expect(loadPrefs(1)).toEqual(DEFAULT_PREFS)
    localStorage.setItem('wisp-map:1', '7')
    expect(loadPrefs(1)).toEqual(DEFAULT_PREFS)
  })

  it('works without storage (private mode, blocked site data)', () => {
    vi.spyOn(Storage.prototype, 'getItem').mockImplementation(() => {
      throw new DOMException('blocked', 'SecurityError')
    })
    vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {
      throw new DOMException('blocked', 'SecurityError')
    })
    expect(() => savePrefs(1, DEFAULT_PREFS)).not.toThrow()
    expect(loadPrefs(1)).toEqual(DEFAULT_PREFS)
  })

  it('hands out a copy of the defaults, never the defaults themselves', () => {
    localStorage.setItem('wisp-map:2', JSON.stringify({ basemap: 'streets' })) // saved before opacity existed
    loadPrefs(2).opacity.radar = 0.2
    expect(DEFAULT_PREFS).toMatchObject({ opacity: {} })
  })
})
