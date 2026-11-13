// A reactive stand-in for Inertia's `page`, so a component test can change its
// props after mounting: vi.mock('@inertiajs/svelte', () => import('@/test/page.svelte'))
export const page = $state({
  flash: {} as { notice?: string; alert?: string },
  // For components that read the user's units (null: imperial)
  props: { auth: { user: null as { unit_system: 'imperial' | 'metric' } | null } },
})
