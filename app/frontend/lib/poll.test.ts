import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { poll, weatherUpdate } from './poll'

describe('poll', () => {
  beforeEach(() => vi.useFakeTimers())
  afterEach(() => vi.useRealTimers())

  it('reloads every interval until stopped', () => {
    const reload = vi.fn()
    const stop = poll(reload, { every: 1000, limit: 60_000 })
    vi.advanceTimersByTime(3500)
    expect(reload).toHaveBeenCalledTimes(3)
    stop()
    vi.advanceTimersByTime(5000)
    expect(reload).toHaveBeenCalledTimes(3)
  })

  it('gives up after the limit, once', () => {
    const reload = vi.fn()
    const ongiveup = vi.fn()
    poll(reload, { every: 1000, limit: 5000, ongiveup })
    vi.advanceTimersByTime(20_000)
    expect(reload).toHaveBeenCalledTimes(4)
    expect(ongiveup).toHaveBeenCalledTimes(1)
  })

  it('says an update failed only while the server still has it running', () => {
    expect(weatherUpdate(true, false)).toBe('updating')
    expect(weatherUpdate(true, true)).toBe('failed')
    expect(weatherUpdate(false, true)).toBeNull()
  })
})
