import { pivots, setup } from '@/routes'

// Where each level of the operation is edited: a system on its own page; a farm, irrigation group
// or field in its dialog on Setup, opened by ?farm=, ?pivot_group= or ?field= (and a planting's by
// ?planting=), which Setup reads once (openFromQuery) and removes from the address

export type EditLevel = 'farm' | 'group' | 'system' | 'field'

export const SETUP_PARAMS = { farm: 'farm', group: 'pivot_group', field: 'field', planting: 'planting' } as const

export function editLink(level: EditLevel, id: number): string {
  if (level === 'system') return pivots.edit(id).url
  return setup.show({ query: { [SETUP_PARAMS[level]]: id } }).url
}

/** The dialog an address asks Setup to open, removing it from the address */
export function takeSetupRequest(): { kind: keyof typeof SETUP_PARAMS; id: number } | null {
  const url = new URL(location.href)
  for (const [kind, param] of Object.entries(SETUP_PARAMS) as [keyof typeof SETUP_PARAMS, string][]) {
    const id = Number(url.searchParams.get(param))
    if (!id) continue
    url.searchParams.delete(param)
    history.replaceState(history.state, '', url)
    return { kind, id }
  }
  return null
}
