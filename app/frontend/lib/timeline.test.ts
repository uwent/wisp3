import { describe, expect, it } from 'vitest'

import { timeline } from './timeline'

const p = (id: number, season_start: string, end_date: string, partial = false) => ({
  id,
  season_start,
  end_date,
  partial,
})

describe('timeline', () => {
  it('runs April to November with one row for a single planting', () => {
    const t = timeline([p(1, '2026-04-01', '2026-11-30')], 2026, '2026-07-01')
    expect(t.from).toBe('2026-04-01')
    expect(t.to).toBe('2026-11-30')
    expect(t.months.map((m) => m.label)).toEqual(['Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov'])
    expect(t.rows).toBe(1)
    expect(t.bars[0]).toMatchObject({ row: 0, left: 0 })
    expect(t.bars[0].width).toBeCloseTo(100)
    expect(t.today).toBeGreaterThan(30)
  })

  it('keeps successions in one row and stacks plots side by side', () => {
    const t = timeline(
      [
        p(1, '2026-04-15', '2026-06-15'),
        p(2, '2026-06-16', '2026-09-01'),
        p(3, '2026-05-01', '2026-09-30', true),
        p(4, '2026-05-01', '2026-09-30', true),
      ],
      2026,
      '2026-07-01',
    )
    const row = (id: number) => t.bars.find((bar) => bar.planting.id === id)!.row
    expect(row(1)).toBe(row(2))
    expect(new Set([row(1), row(3), row(4)]).size).toBe(3)
    expect(t.rows).toBe(3)
  })

  it('widens the axis to whole months for plantings outside the usual season', () => {
    const t = timeline([p(1, '2026-03-10', '2026-12-05')], 2026, '2027-01-01')
    expect(t.from).toBe('2026-03-01')
    expect(t.to).toBe('2026-12-31')
    expect(t.today).toBeNull()
  })

  it('places a bar by its dates', () => {
    const t = timeline([p(1, '2026-06-01', '2026-06-30')], 2026, '2026-07-01')
    const bar = t.bars[0]
    const days = 244 // Apr 1 – Nov 30
    expect(bar.left).toBeCloseTo((61 / days) * 100)
    expect(bar.width).toBeCloseTo((30 / days) * 100)
  })
})
