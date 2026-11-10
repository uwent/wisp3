import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { poll, weatherUpdate } from './poll'

describe('poll', () => {
  beforeEach(() => vi.useFakeTimers())
  afterEach(() => vi.useRealTimers())

  it('reloads only when one of the pending pivots has landed, once per landing', async () => {
    let updating = [1, 2, 3]
    let pending = [1, 2]
    const check = vi.fn(async () => updating)
    const reload = vi.fn((done: () => void) => {
      pending = pending.filter((id) => updating.includes(id))
      done()
    })
    const stop = poll(() => pending, reload, { every: 1000, limit: 60_000, check })

    await vi.advanceTimersByTimeAsync(3500)
    expect(check).toHaveBeenCalledTimes(3)
    expect(reload).not.toHaveBeenCalled()

    updating = [2, 3]
    await vi.advanceTimersByTimeAsync(1000)
    expect(reload).toHaveBeenCalledTimes(1)
    await vi.advanceTimersByTimeAsync(2000)
    expect(reload).toHaveBeenCalledTimes(1) // pivot 3 isn't on this page

    stop()
    updating = []
    await vi.advanceTimersByTimeAsync(5000)
    expect(check).toHaveBeenCalledTimes(6)
    expect(reload).toHaveBeenCalledTimes(1)
  })

  it("doesn't check again while a reload is on its way, and ignores a failed check", async () => {
    let finish: () => void = () => {}
    let result: number[] | null = null
    const check = vi.fn(async () => result)
    const reload = vi.fn((done: () => void) => (finish = done))
    poll(() => [1], reload, { every: 1000, limit: 60_000, check })

    await vi.advanceTimersByTimeAsync(1000)
    expect(reload).not.toHaveBeenCalled()
    result = []
    await vi.advanceTimersByTimeAsync(3000)
    expect(reload).toHaveBeenCalledTimes(1)
    expect(check).toHaveBeenCalledTimes(2)
    finish()
    await vi.advanceTimersByTimeAsync(1000)
    expect(reload).toHaveBeenCalledTimes(2)
  })

  it('gives up after the limit, once', async () => {
    const check = vi.fn(async () => [1])
    const ongiveup = vi.fn()
    poll(() => [1], vi.fn(), { every: 1000, limit: 5000, ongiveup, check })
    await vi.advanceTimersByTimeAsync(20_000)
    expect(check).toHaveBeenCalledTimes(4)
    expect(ongiveup).toHaveBeenCalledTimes(1)
  })

  it('says an update failed only while the server still has it running', () => {
    expect(weatherUpdate(true, false)).toBe('updating')
    expect(weatherUpdate(true, true)).toBe('failed')
    expect(weatherUpdate(false, true)).toBeNull()
  })
})
