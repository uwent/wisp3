import { afterEach, describe, expect, it, vi } from 'vitest'

import type { Boundary } from '@/lib/boundary'

import { forgetAllKept, forgetKept, KEEP_FOR_MS, keepShapes, keptKey, readAt, readKept, toKept } from './kept'
import type { ImportedShape } from './read'

const square: Boundary = {
  type: 'Polygon',
  coordinates: [
    [
      [-89.5, 44.1],
      [-89.49, 44.1],
      [-89.49, 44.11],
      [-89.5, 44.11],
      [-89.5, 44.1],
    ],
  ],
}
const shape = (name: string, problems: string[] = []): ImportedShape => ({
  properties: { NAME: name, ACRES: 80 },
  boundary: square,
  acres: 80,
  notes: [],
  problems,
})
const file = {
  fileName: 'Fields.zip',
  nameKey: 'NAME',
  skipped: 1,
  shapes: [shape('East 40'), shape('Dane County', ['is larger than a field (at most 1,500 acres)'])],
}
const NOW = Date.UTC(2026, 6, 20, 19, 14)

describe('kept outline shapes', () => {
  afterEach(() => {
    localStorage.clear()
    vi.restoreAllMocks()
  })

  it("keeps a file's shapes in the browser, per operation, without the outlines of those that can't be saved", () => {
    expect(keepShapes(7, file, NOW)).toBe(true)
    expect(localStorage.getItem(keptKey(7))).not.toBeNull()
    const kept = readKept(7, NOW + 1000)!
    expect(kept.fileName).toBe('Fields.zip')
    expect(kept.savedAt).toBe(NOW)
    expect(kept.nameKey).toBe('NAME')
    expect(kept.skipped).toBe(1)
    expect(kept.shapes[0].boundary).toEqual(square)
    expect(kept.shapes[1].boundary).toBeNull()
    expect(kept.shapes[1].problems).toEqual(['is larger than a field (at most 1,500 acres)'])
    expect(kept.shapes[1].properties).toEqual({ NAME: 'Dane County', ACRES: 80 })
    // Another operation's are its own
    expect(readKept(8, NOW)).toBeNull()
  })

  it('keeps nothing without an operation', () => {
    expect(keepShapes(null, file, NOW)).toBe(false)
    expect(readKept(null, NOW)).toBeNull()
  })

  it('forgets them after a week, or when asked', () => {
    keepShapes(7, file, NOW)
    expect(readKept(7, NOW + KEEP_FOR_MS)).not.toBeNull()
    expect(readKept(7, NOW + KEEP_FOR_MS + 1)).toBeNull()
    expect(localStorage.getItem(keptKey(7))).toBeNull()

    keepShapes(7, file, NOW)
    forgetKept(7)
    expect(readKept(7, NOW)).toBeNull()
  })

  it("treats what isn't kept shapes as none, and removes it", () => {
    const malformed = [
      'text',
      { ...toKept(file, NOW), shapes: [] },
      { ...toKept(file, NOW), savedAt: 'yesterday' },
      { ...toKept(file, NOW), shapes: [{ ...toKept(file, NOW).shapes[0], boundary: null }] },
      { ...toKept(file, NOW), shapes: [{ ...toKept(file, NOW).shapes[0], boundary: { type: 'Point' } }] },
      { ...toKept(file, NOW), shapes: [{ ...toKept(file, NOW).shapes[0], properties: [] }] },
    ]
    for (const value of malformed) {
      localStorage.setItem(keptKey(7), JSON.stringify(value))
      expect(readKept(7, NOW)).toBeNull()
      expect(localStorage.getItem(keptKey(7))).toBeNull()
    }
  })

  it("carries on when storage is blocked or full, and doesn't leave an older file in its place", () => {
    keepShapes(7, { ...file, fileName: 'Older.zip' }, NOW)
    vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {
      throw new Error('QuotaExceededError')
    })
    expect(keepShapes(7, file, NOW)).toBe(false)
    expect(readKept(7, NOW)).toBeNull()

    vi.spyOn(Storage.prototype, 'getItem').mockImplementation(() => {
      throw new Error('blocked')
    })
    expect(readKept(7, NOW)).toBeNull()
  })

  it('says when they were read', () => {
    const at = new Date(2026, 6, 20, 14, 14).getTime()
    expect(readAt(at, at + 60_000)).toBe('read at 2:14 pm')
    expect(readAt(at, new Date(2026, 6, 21, 9, 0).getTime())).toBe('read yesterday at 2:14 pm')
    expect(readAt(at, new Date(2026, 6, 24, 9, 0).getTime())).toBe('read Jul 20 at 2:14 pm')
  })

  it("forgets every operation's shapes on signing out, and nothing else", () => {
    keepShapes(7, file, NOW)
    keepShapes(8, file, NOW)
    localStorage.setItem('wisp:other', '1')
    forgetAllKept()
    expect(readKept(7, NOW)).toBeNull()
    expect(readKept(8, NOW)).toBeNull()
    expect(localStorage.getItem('wisp:other')).toBe('1')
  })
})
