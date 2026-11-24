import { router } from '@inertiajs/svelte'
import type { RequestPayload } from '@inertiajs/core'

type Route = { url: string; method: 'get' | 'post' | 'put' | 'patch' | 'delete' }

export const NO_CONNECTION = "Couldn't reach WISP, so this wasn't saved. Check your connection and try again."
export const SIGNED_OUT =
  "You've been signed out, so this wasn't saved. Sign in again in another tab, then save it here."
export const NOT_SAVED = "WISP couldn't save this. Try again in a moment."

// Saves go one at a time: a visit interrupts the one before it, which would cancel an earlier
// cell's save that's still on its way when the next cell is saved
let last: Promise<unknown> = Promise.resolve()

/**
 * Submits data and reloads the page's props in place (keeping scroll and component state, as for
 * a grid edit). only: the props to reload (the rest, and the charts drawn from them, stay as they
 * are). Resolves with null on success, or a message: the first error, or why the request failed.
 */
export function save(route: Route, data: RequestPayload, { only }: { only?: string[] } = {}): Promise<string | null> {
  const result = last.then(() => send(route, data, only))
  last = result
  return result
}

function send(route: Route, data: RequestPayload, only?: string[]): Promise<string | null> {
  return new Promise((resolve) => {
    router.visit(route.url, {
      method: route.method,
      data,
      preserveScroll: true,
      preserveState: true,
      ...(only ? { only } : {}),
      onSuccess: () => resolve(null),
      onError: (errors) => {
        const [first] = Object.values(errors)
        resolve((Array.isArray(first) ? first[0] : first) ?? 'Could not save')
      },
      onCancel: () => resolve('Cancelled'),
      // Inertia calls neither onSuccess nor onError when the request never arrives or the server
      // answers with an error page, so these settle the save. The caller shows the message, so
      // the page's own notice of a lost connection (entrypoints/inertia.ts) is skipped.
      onNetworkError: () => {
        resolve(NO_CONNECTION)
        return false
      },
      onHttpException: (response) => resolve(response.status === 401 ? SIGNED_OUT : NOT_SAVED),
      onFinish: () => resolve(NOT_SAVED),
    })
  })
}
