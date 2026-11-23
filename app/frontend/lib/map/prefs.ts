import type { LngLat } from '@/lib/geo'
import type { SortOrder } from '@/lib/overview'
import { readStored, writeStored } from '@/lib/storage'

import type { Basemap } from './basemaps'
import { OVERLAYS } from './overlays'

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
  /** Draw the irrigation systems' shapes (off to see outlined fields alone) */
  systems: boolean
}

export const DEFAULT_PREFS: MapPrefs = {
  view: null,
  basemap: 'imagery',
  sort: 'urgent',
  listOpen: true,
  rain: null,
  overlays: [],
  opacity: {},
  systems: true,
}

const key = (groupId: number | undefined) => `wisp-map:${groupId ?? 'none'}`

// A fresh copy, so changing a loaded setting's list or map in place never changes the defaults
const defaults = (): MapPrefs => structuredClone(DEFAULT_PREFS)

export function loadPrefs(groupId: number | undefined): MapPrefs {
  const saved = readStored(key(groupId)) as Partial<Record<keyof MapPrefs, unknown>> | undefined
  if (!saved || typeof saved !== 'object') return defaults()
  // Layers saved earlier that the map no longer has are dropped
  const known = (id: unknown) => OVERLAYS.some((overlay) => overlay.id === id)
  return {
    ...defaults(),
    ...saved,
    rain: known(saved.rain) ? saved.rain : null,
    overlays: Array.isArray(saved.overlays) ? saved.overlays.filter(known) : [],
  } as MapPrefs
}

export function savePrefs(groupId: number | undefined, prefs: MapPrefs) {
  // Storage blocked (private mode): the settings last for this page only
  writeStored(key(groupId), prefs)
}
