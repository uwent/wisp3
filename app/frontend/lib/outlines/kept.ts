import type { Boundary } from '@/lib/boundary'
import { readStored, removeStored, writeStored } from '@/lib/storage'

import type { ImportedShape } from './read'

// The last outline file's shapes, kept for the tab's session (sessionStorage) per operation, so
// outlining fields one at a time on their shape pages, or finishing in Setup's import what was
// left there, doesn't mean reading the same file again. Kept a day at most. A shape that can't be
// saved keeps its attributes and its problems but not its outline, which is what takes the room
// (a county file's shapes, all too large for a field, would otherwise outgrow the storage). If the
// file is still too big to keep, it isn't kept, and nothing says so.

/** A shape as kept: one that can't be saved has no outline */
export type KeptShape = Omit<ImportedShape, 'boundary'> & { boundary: Boundary | null }

export type KeptFile = {
  fileName: string
  /** When it was read, in ms */
  savedAt: number
  nameKey: string | null
  /** Features that aren't polygons, left out */
  skipped: number
  shapes: KeptShape[]
}

export const KEEP_FOR_MS = 24 * 60 * 60 * 1000

export const keptKey = (groupId: number) => `wisp:outline-shapes:${groupId}`

/** A file read, as it's kept: shapes that can't be saved lose their outlines */
export function toKept(
  file: { fileName: string; nameKey: string | null; skipped: number; shapes: ImportedShape[] },
  now = Date.now(),
): KeptFile {
  return {
    fileName: file.fileName,
    savedAt: now,
    nameKey: file.nameKey,
    skipped: file.skipped,
    shapes: file.shapes.map(({ properties, boundary, acres, notes, problems }) => ({
      properties,
      boundary: problems.length ? null : boundary,
      acres,
      notes,
      problems,
    })),
  }
}

/** Keeps a file's shapes for the operation; false when they couldn't be (no group, storage full or blocked) */
export function keepShapes(groupId: number | null | undefined, file: Parameters<typeof toKept>[0], now = Date.now()) {
  if (groupId === null || groupId === undefined) return false
  const key = keptKey(groupId)
  if (writeStored(key, toKept(file, now), 'session')) return true
  // Too big: an older file mustn't stay in its place
  removeStored(key, 'session')
  return false
}

/** The operation's kept shapes, or null when there are none, they're over a day old, or what's stored isn't them */
export function readKept(groupId: number | null | undefined, now = Date.now()): KeptFile | null {
  if (groupId === null || groupId === undefined) return null
  const key = keptKey(groupId)
  const value = readStored(key, 'session')
  if (value === undefined) return null
  if (!isKeptFile(value) || now - value.savedAt > KEEP_FOR_MS || value.savedAt > now + 60_000) {
    removeStored(key, 'session')
    return null
  }
  return value
}

export function forgetKept(groupId: number | null | undefined) {
  if (groupId !== null && groupId !== undefined) removeStored(keptKey(groupId), 'session')
}

/** When a kept file was read, for its heading: "read at 2:14 pm", or "read yesterday at 2:14 pm" */
export function readAt(savedAt: number, now = Date.now()): string {
  const at = new Date(savedAt)
  const time = at.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' }).toLowerCase()
  return at.toDateString() === new Date(now).toDateString() ? `read at ${time}` : `read yesterday at ${time}`
}

// Storage can hold anything: each part is checked

const isObject = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value)
const isStrings = (value: unknown): value is string[] =>
  Array.isArray(value) && value.every((item) => typeof item === 'string')
const isNumber = (value: unknown): value is number => typeof value === 'number' && Number.isFinite(value)

function isBoundary(value: unknown): value is Boundary {
  if (!isObject(value) || value.type !== 'Polygon' || !Array.isArray(value.coordinates)) return false
  const [ring, ...rest] = value.coordinates as unknown[]
  return (
    rest.length === 0 &&
    Array.isArray(ring) &&
    ring.length >= 4 &&
    ring.every((position) => Array.isArray(position) && position.length === 2 && position.every(isNumber))
  )
}

function isKeptShape(value: unknown): value is KeptShape {
  if (!isObject(value) || !isObject(value.properties) || !isNumber(value.acres)) return false
  if (!isStrings(value.notes) || !isStrings(value.problems)) return false
  // One that can be saved has its outline
  return value.boundary === null ? value.problems.length > 0 : isBoundary(value.boundary)
}

function isKeptFile(value: unknown): value is KeptFile {
  return (
    isObject(value) &&
    typeof value.fileName === 'string' &&
    isNumber(value.savedAt) &&
    (value.nameKey === null || typeof value.nameKey === 'string') &&
    isNumber(value.skipped) &&
    Array.isArray(value.shapes) &&
    value.shapes.length > 0 &&
    value.shapes.every(isKeptShape)
  )
}
