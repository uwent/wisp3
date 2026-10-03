import { describe, expect, it } from 'vitest'

import { addDays, daysBetween, formatDate, relativeDay } from './dates'
import { formatNumber, parseNumber, units } from './units'

describe('units', () => {
  const imperial = units('imperial')
  const metric = units('metric')

  it('formats stored inches in either system', () => {
    expect(imperial.format('depth', 0.75)).toBe('0.75 in')
    expect(metric.format('depth', 1)).toBe('25.4 mm')
    expect(metric.format('depth', 0.8, { unit: false })).toBe('20.3')
  })

  it('shows missing values as a dash, and zero as zero', () => {
    expect(imperial.format('depth', null)).toBe('—')
    expect(imperial.format('depth', undefined)).toBe('—')
    expect(imperial.format('depth', 0)).toBe('0.00 in')
    expect(imperial.format('depth', -0.0001)).toBe('0.00 in')
  })

  it('parses input back to stored units', () => {
    expect(imperial.parse('depth', '0.8')).toEqual({ ok: true, value: 0.8 })
    const mm = metric.parse('depth', '25.4')
    expect(mm.ok && mm.value).toBeCloseTo(1)
  })

  it('treats blank as not entered and 0 as entered zero', () => {
    expect(metric.parse('depth', '  ')).toEqual({ ok: true, value: null })
    expect(metric.parse('depth', '0')).toEqual({ ok: true, value: 0 })
  })

  it('rejects text that is not a number', () => {
    expect(imperial.parse('depth', 'lots')).toEqual({ ok: false, error: 'Enter a number' })
    expect(parseNumber('1,250')).toEqual({ ok: true, value: 1250 })
  })

  it('round-trips through input boxes', () => {
    const shown = metric.input('depth', 0.75)
    expect(shown).toBe('19.05')
    const back = metric.parse('depth', shown)
    expect(back.ok && back.value).toBeCloseTo(0.75, 4)
    expect(imperial.input('depth', 0.5)).toBe('0.5')
    expect(imperial.input('depth', null)).toBe('')
  })

  it('converts temperature with its offset, and degree days without', () => {
    expect(metric.format('temperature', 212)).toBe('100 °C')
    expect(metric.toStored('temperature', 0)).toBe(32)
    expect(metric.format('degreeDays', 900)).toBe('500 °C·d')
  })

  it('converts area, flow, root depth and radius', () => {
    expect(metric.format('area', 100)).toBe('40.5 ha')
    expect(metric.format('flow', 900)).toBe('56.8 L/s')
    expect(metric.format('rootDepth', 24)).toBe('61 cm')
    expect(metric.format('distance', 1300)).toBe('396 m')
    expect(metric.label('speed')).toBe('km/h')
  })

  it('formats plain numbers with grouping', () => {
    expect(formatNumber(1234.5, 1)).toBe('1,234.5')
    expect(formatNumber(null)).toBe('—')
  })
})

describe('dates', () => {
  it('does calendar arithmetic without time zone shifts', () => {
    expect(addDays('2026-02-28', 1)).toBe('2026-03-01')
    expect(addDays('2026-03-08', -1)).toBe('2026-03-07')
    expect(daysBetween('2026-07-01', '2026-07-15')).toBe(14)
  })

  it('formats dates for people', () => {
    expect(formatDate('2026-07-01')).toBe('Jul 1')
    expect(formatDate('2026-07-01', { year: true })).toBe('Jul 1, 2026')
    expect(relativeDay('2026-07-14', '2026-07-15')).toBe('yesterday')
    expect(relativeDay('2026-07-10', '2026-07-15')).toBe('5 days ago')
  })
})
