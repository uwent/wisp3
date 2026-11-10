// Waiting on the server while it fetches a pivot's weather (a new or moved pivot, or a cell with
// weather missing), for an $effect:
//   $effect(() => { if (updating) return poll(() => updatingIds, (done) => router.reload({ only: ['farms'], onFinish: done })) })
// Every few seconds it asks which of the group's pivots are still updating (a cheap check that reads
// only the cache), and reloads the page's data only when one of the page's pivots has landed, so a
// page with many fields isn't rebuilt on every check. Giving up suggests the job failed (WISP isn't
// rate limited in practice), so pages say so then.

import { weatherUpdates } from '@/routes'

export const POLL_EVERY = 5000
/** Give up after this long, in case a job is stuck waiting on a rate limit */
export const POLL_LIMIT = 3 * 60 * 1000

/** Where a pivot's weather update stands for the page: running, given up on, or neither */
export type WeatherUpdate = 'updating' | 'failed' | null

export const weatherUpdate = (updating: boolean, timedOut: boolean): WeatherUpdate =>
  updating ? (timedOut ? 'failed' : 'updating') : null

/** The ids of the group's pivots whose weather is updating, or null if the check failed */
export async function updatingPivotIds(): Promise<number[] | null> {
  try {
    const response = await fetch(weatherUpdates.show().url, { headers: { Accept: 'application/json' } })
    if (!response.ok) return null
    return ((await response.json()) as { pivot_ids: number[] }).pivot_ids
  } catch {
    return null
  }
}

/**
 * Every `every` ms, checks whether any of `pending()` (the page's updating pivots, read from its
 * current props) has landed, and if so calls reload, which calls done when the page has its new
 * data. After `limit` ms it stops and calls ongiveup. Returns the cleanup that stops it.
 */
export function poll(
  pending: () => number[],
  reload: (done: () => void) => void,
  {
    every = POLL_EVERY,
    limit = POLL_LIMIT,
    ongiveup,
    check = updatingPivotIds,
  }: {
    every?: number
    limit?: number
    ongiveup?: () => void
    check?: () => Promise<number[] | null>
  } = {},
): () => void {
  const started = Date.now()
  let busy = false
  let stopped = false
  const timer = setInterval(async () => {
    if (Date.now() - started >= limit) {
      stop()
      ongiveup?.()
      return
    }
    if (busy) return
    busy = true
    const updating = await check()
    if (stopped || !updating) {
      busy = false
      return
    }
    const still = new Set(updating)
    if (pending().some((id) => !still.has(id))) reload(() => (busy = false))
    else busy = false
  }, every)
  function stop() {
    stopped = true
    clearInterval(timer)
  }
  return stop
}
