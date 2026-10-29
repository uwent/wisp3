import { router } from '@inertiajs/svelte'
import { afterEach, describe, expect, it, vi } from 'vitest'

import { save } from './save'

type Callbacks = { onSuccess: () => void; onError: (errors: Record<string, unknown>) => void; onCancel: () => void }

/** Stubs router.visit to answer with one of its callbacks, and returns the stub */
function visitAnswering(answer: (callbacks: Callbacks) => void) {
  return vi.spyOn(router, 'visit').mockImplementation((_url, options) => answer(options as unknown as Callbacks))
}

afterEach(() => vi.restoreAllMocks())

describe('save', () => {
  const route = { url: '/fields/1/days/2026-07-01', method: 'patch' as const }

  it('submits in place, keeping scroll and state, and reloads only the props asked for', async () => {
    const visit = visitAnswering((callbacks) => callbacks.onSuccess())
    expect(await save(route, { day: { rain_in: 0.5 } }, { only: ['days'] })).toBeNull()
    expect(visit).toHaveBeenCalledWith(
      route.url,
      expect.objectContaining({
        method: 'patch',
        data: { day: { rain_in: 0.5 } },
        preserveScroll: true,
        preserveState: true,
        only: ['days'],
      }),
    )
    await save(route, {})
    expect(visit.mock.lastCall![1]).not.toHaveProperty('only')
  })

  it("resolves with the server's first error, whether a message or a list of them", async () => {
    visitAnswering((callbacks) => callbacks.onError({ rain_in: 'must be at least 0', canopy: 'too high' }))
    expect(await save(route, {})).toBe('must be at least 0')
    visitAnswering((callbacks) => callbacks.onError({ rain_in: ['must be at least 0', 'is odd'] }))
    expect(await save(route, {})).toBe('must be at least 0')
  })

  it('says so when it fails without a message, or is cancelled', async () => {
    visitAnswering((callbacks) => callbacks.onError({}))
    expect(await save(route, {})).toBe('Could not save')
    visitAnswering((callbacks) => callbacks.onCancel())
    expect(await save(route, {})).toBe('Cancelled')
  })
})
