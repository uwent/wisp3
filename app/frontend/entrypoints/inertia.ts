import { createInertiaApp, router } from '@inertiajs/svelte'

import AppLayout from '@/layouts/AppLayout.svelte'
import AuthLayout from '@/layouts/AuthLayout.svelte'
import { startAnalytics } from '@/lib/analytics'
import { NO_CONNECTION_NOTICE, SIGNED_OUT_NOTICE } from '@/lib/requestFailures'
import { watchHistoryMoves } from '@/lib/unsaved.svelte'

// Google Analytics on the public pages, when configured (before the app, to see its first page)
startAnalytics()

// Before Inertia listens for Back and Forward, so unsaved changes can be asked about first
watchHistoryMoves()

createInertiaApp({
  pages: '../pages',

  // Sign-in, sign-up and other signed-out pages use the centered card layout
  layout: (name) => (name.startsWith('Auth/') ? AuthLayout : AppLayout),

  title: (title) => (title ? `${title} · WISP` : 'WISP'),

  progress: { color: 'var(--color-brand-500)' },

  defaults: {
    form: {
      forceIndicesArrayFormatInFormData: false,
      withAllErrors: true,
    },
    visitOptions: () => {
      return { queryStringArrayFormat: 'brackets' }
    },
  },
})

// A request that never reached WISP (no signal at the field's edge) says so, where Inertia would
// do nothing: the page and what's typed on it stay as they are, to try again
router.on('networkError', () => {
  router.flash('alert', NO_CONNECTION_NOTICE)
  return false
})

// A save after the session ended is answered 401 (Users::FailureApp), which leaves the page and
// what's typed on it in place, where a redirect to sign in would drop it
router.on('httpException', (event) => {
  if (event.detail.response.status !== 401) return
  router.flash('alert', SIGNED_OUT_NOTICE)
  return false
})
