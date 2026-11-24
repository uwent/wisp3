import type { LngLat } from '@/lib/geo'
import type { SortOrder } from '@/lib/overview'
import { readStored, writeStored } from '@/lib/storage'

import type { Basemap } from './basemaps'
import { OVERLAYS } from './overlays'

// The map page's settings, remembered per operation in this browser: the view, basemap, overlays
// and layers, list order and whether the list is open. Storage can be blocked or cleared, so every
// read and write is guarded and the page works without it.

export type MapPrefs = {
  view: { center: LngLat; zoom: number } | null
  basemap: Basemap
  sort: SortOrder
  listOpen: boolean
  /** The data overlay shown (one at a time: rain or the Drought Monitor), or null */
  overlay: string | null
  /** Overlay opacity by id, where the user changed it */
  opacity: Record<string, number>
  /** Draw the irrigation systems' shapes (off to see outlined fields alone) */
  systems: boolean
  /** Outline the weather zones of the operation's systems, with their weather on hover */
  zones: boolean
}

export const DEFAULT_PREFS: MapPrefs = {
  view: null,
  basemap: 'imagery',
  sort: 'urgent',
  listOpen: true,
  overlay: null,
  opacity: {},
  systems: true,
  zones: true,
}

const key = (groupId: number | undefined) => `wisp-map:${groupId ?? 'none'}`

// A fresh copy, so changing a loaded setting's list or map in place never changes the defaults
const defaults = (): MapPrefs => structuredClone(DEFAULT_PREFS)

export function loadPrefs(groupId: number | undefined): MapPrefs {
  const stored = readStored(key(groupId))
  if (!stored || typeof stored !== 'object') return defaults()
  // Saved before one overlay at a time: a rain layer and a list of others, the rain layer kept first
  const { rain, overlays, ...saved } = stored as Partial<Record<keyof MapPrefs | 'rain' | 'overlays', unknown>>
  // Layers saved earlier that the map no longer has are dropped
  const known = (id: unknown) => OVERLAYS.some((overlay) => overlay.id === id)
  const overlay = [saved.overlay, rain, ...(Array.isArray(overlays) ? overlays : [])].find(known) ?? null
  return { ...defaults(), ...saved, overlay } as MapPrefs
}

export function savePrefs(groupId: number | undefined, prefs: MapPrefs) {
  // Storage blocked (private mode): the settings last for this page only
  writeStored(key(groupId), prefs)
}
