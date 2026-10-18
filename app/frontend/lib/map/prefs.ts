import type { LngLat } from '@/lib/geo'
import type { SortOrder } from '@/lib/overview'

import type { Basemap } from './basemaps'

// The map page's settings, remembered per operation in this browser: the view, basemap, overlays,
// list order and whether the list is open. Storage can be blocked or cleared, so every read and
// write is guarded and the page works without it.

export type MapPrefs = {
  view: { center: LngLat; zoom: number } | null
  basemap: Basemap
  sort: SortOrder
  listOpen: boolean
  /** The rain overlay shown (one at a time), or null */
  rain: string | null
  /** The other overlays shown */
  overlays: string[]
  /** Overlay opacity by id, where the user changed it */
  opacity: Record<string, number>
}

export const DEFAULT_PREFS: MapPrefs = {
  view: null,
  basemap: 'imagery',
  sort: 'urgent',
  listOpen: true,
  rain: null,
  overlays: [],
  opacity: {},
}

const key = (groupId: number | undefined) => `wisp-map:${groupId ?? 'none'}`

export function loadPrefs(groupId: number | undefined): MapPrefs {
  try {
    const saved = JSON.parse(localStorage.getItem(key(groupId)) ?? 'null')
    return saved && typeof saved === 'object' ? { ...DEFAULT_PREFS, ...saved } : { ...DEFAULT_PREFS }
  } catch {
    return { ...DEFAULT_PREFS }
  }
}

export function savePrefs(groupId: number | undefined, prefs: MapPrefs) {
  try {
    localStorage.setItem(key(groupId), JSON.stringify(prefs))
  } catch {
    // Storage blocked (private mode): the settings last for this page only
  }
}
