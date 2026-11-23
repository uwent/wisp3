import { router } from '@inertiajs/svelte'

import { poll, weatherUpdate } from './poll'

/**
 * A page's wait for its systems' weather (lib/poll.ts): while pending() (read from the page's props)
 * lists systems whose weather is updating, polls, reloading the page's data (only those props, if
 * given) once one lands; after POLL_LIMIT it gives up. state(updating) is where a system's (or the
 * page's) update stands: 'updating', 'failed' or null. Call it while the component initializes.
 */
export function pollWeather(pending: () => number[], only?: string[]) {
  let timedOut = $state(false)
  const active = $derived(pending().length > 0)
  $effect(() => {
    if (!active) return
    timedOut = false
    return poll(pending, (done) => router.reload({ ...(only && { only }), onFinish: done }), {
      ongiveup: () => (timedOut = true),
    })
  })
  return { state: (updating: boolean) => weatherUpdate(updating, timedOut) }
}
