import { router } from '@inertiajs/svelte'
import type { RequestPayload } from '@inertiajs/core'

type Route = { url: string; method: 'get' | 'post' | 'put' | 'patch' | 'delete' }

/**
 * Submits data and reloads the page's props in place (keeping scroll and component state, as for
 * a grid edit). Resolves with null on success, or the first error message.
 */
export function save(route: Route, data: RequestPayload): Promise<string | null> {
  return new Promise((resolve) => {
    router.visit(route.url, {
      method: route.method,
      data,
      preserveScroll: true,
      preserveState: true,
      onSuccess: () => resolve(null),
      onError: (errors) => {
        const [first] = Object.values(errors)
        resolve((Array.isArray(first) ? first[0] : first) ?? 'Could not save')
      },
      onCancel: () => resolve('Cancelled'),
    })
  })
}
