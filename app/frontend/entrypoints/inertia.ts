import { createInertiaApp } from '@inertiajs/svelte'

import AppLayout from '@/layouts/AppLayout.svelte'
import AuthLayout from '@/layouts/AuthLayout.svelte'

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
