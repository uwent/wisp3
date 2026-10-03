import { router } from '@inertiajs/svelte'

export const UNSAVED_MESSAGE = 'You have unsaved changes. Leave this page without saving them?'

/**
 * Asks before leaving a page with unsaved changes: links and other Inertia visits get a confirm,
 * and closing or reloading the tab gets the browser's own prompt. Submitting the form (any
 * non-GET visit) isn't stopped. Call during component setup; it's removed with the component.
 */
export function confirmUnsavedChanges(isDirty: () => boolean) {
  $effect(() => {
    const offBefore = router.on('before', (event) => {
      if (event.detail.visit.method !== 'get' || !isDirty()) return
      if (!confirm(UNSAVED_MESSAGE)) return false
    })
    const onUnload = (event: BeforeUnloadEvent) => {
      if (isDirty()) event.preventDefault()
    }
    addEventListener('beforeunload', onUnload)
    return () => {
      offBefore()
      removeEventListener('beforeunload', onUnload)
    }
  })
}
