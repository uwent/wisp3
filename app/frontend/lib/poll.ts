// Reloading a page while the server is working on something (weather for a new or moved pivot),
// for an $effect: `$effect(() => { if (updating) return poll(() => router.reload({ only: ['farms'] })) })`.
// Giving up suggests the job failed (WISP isn't rate limited in practice), so pages say so then.

export const POLL_EVERY = 5000
/** Give up after this long, in case a job is stuck waiting on a rate limit */
export const POLL_LIMIT = 3 * 60 * 1000

/** Where a pivot's weather update stands for the page: running, given up on, or neither */
export type WeatherUpdate = 'updating' | 'failed' | null

export const weatherUpdate = (updating: boolean, timedOut: boolean): WeatherUpdate =>
  updating ? (timedOut ? 'failed' : 'updating') : null

/**
 * Calls reload every `every` ms until `limit` ms have passed, then ongiveup; returns the cleanup
 * that stops it
 */
export function poll(
  reload: () => void,
  { every = POLL_EVERY, limit = POLL_LIMIT, ongiveup }: { every?: number; limit?: number; ongiveup?: () => void } = {},
): () => void {
  const started = Date.now()
  const timer = setInterval(() => {
    if (Date.now() - started < limit) return reload()
    clearInterval(timer)
    ongiveup?.()
  }, every)
  return () => clearInterval(timer)
}
