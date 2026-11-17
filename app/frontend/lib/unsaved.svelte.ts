import { router } from '@inertiajs/svelte'

import { type Change, ChangeTracker, describeChanges } from '@/lib/formChanges'

export const UNSAVED_MESSAGE = 'You have unsaved changes. Leave this page without saving them?'

/** The confirm's text: the changes listed (G.13) when the form's are known, else the plain question */
export function unsavedMessage(tracker?: ChangeTracker): string {
  return changesMessage(tracker ? tracker.changes() : []) ?? UNSAVED_MESSAGE
}

/** A confirm listing changes before leaving them (a page, or a dialog's form), or null without any */
export function changesMessage(changes: Change[], leaving = 'this page'): string | null {
  const lines = describeChanges(changes)
  if (!lines.length) return null
  return `You have unsaved changes:\n\n${lines.map((line) => `• ${line}`).join('\n')}\n\nLeave ${leaving} without saving them?`
}

/**
 * Asks before leaving a page with unsaved changes: links and other Inertia visits get a confirm,
 * listing what changed in `form` (an element holding the page's form, looked up when asked), and
 * closing or reloading the tab gets the browser's own prompt (its text can't be changed).
 * Submitting the form (any non-GET visit) isn't stopped. Call during component setup; it's removed
 * with the component. Returns the message, for a page that asks on its own too.
 */
export function confirmUnsavedChanges(isDirty: () => boolean, form?: () => Element | null | undefined) {
  const tracker = form ? new ChangeTracker(form, () => !isDirty()) : undefined
  $effect(() => {
    tracker?.start()
    const offBefore = router.on('before', (event) => {
      if (event.detail.visit.method !== 'get' || !isDirty()) return
      if (!confirm(unsavedMessage(tracker))) return false
    })
    const onUnload = (event: BeforeUnloadEvent) => {
      if (isDirty()) event.preventDefault()
    }
    addEventListener('beforeunload', onUnload)
    return () => {
      tracker?.stop()
      offBefore()
      removeEventListener('beforeunload', onUnload)
    }
  })
  return { message: () => unsavedMessage(tracker) }
}
