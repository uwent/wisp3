import { createInertiaApp } from '@inertiajs/svelte'

import AppLayout from '@/layouts/AppLayout.svelte'
import AuthLayout from '@/layouts/AuthLayout.svelte'
import { startAnalytics } from '@/lib/analytics'

// Google Analytics on the public pages, when configured (before the app, to see its first page)
startAnalytics()

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
