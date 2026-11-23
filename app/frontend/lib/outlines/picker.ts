import { type Boundary, boundaryRing } from '@/lib/boundary'

import type { KeptShape } from './kept'
import { type ImportSystem, matchField } from './matching'
import { systemDistanceM } from './problems'
import { shapeName, shapeNotes } from './read'

// Picking one field's shape from a file's, kept pure for testing: the
// shape named as the field comes first, then the nearest its system; those already used for another
// field say so

/** A shape on offer: one just read (ImportedShape) or kept (one that can't be saved has no outline) */
export type PickerShape = KeptShape

export type PickerRow = {
  /** Its place in the file */
  index: number
  shape: PickerShape
  /** Its name under the chosen attribute, or '' */
  name: string
  usable: boolean
  /** Its name is the field's, so it's offered first */
  match: 'name' | null
  /** Meters from the shape to the field's system (0 overlapping it), or null for one that can't be saved */
  meters: number | null
  /** The other field whose shape it already is, or null; 'this field' for the field's own */
  usedBy: string | null
}

export type PickerContext = {
  field: { id: number; name: string; pivot_id: number; boundary: Boundary | null }
  system: ImportSystem
  otherFields: { name: string; boundary: Boundary }[]
}

/** Whether two outlines are the same, position by position (as saved, rounded to 7 places) */
export function sameBoundary(a: Boundary, b: Boundary, tolerance = 1e-6): boolean {
  const [x, y] = [boundaryRing(a), boundaryRing(b)]
  if (x.length !== y.length) return false
  return x.every(
    (position, i) => Math.abs(position[0] - y[i][0]) <= tolerance && Math.abs(position[1] - y[i][1]) <= tolerance,
  )
}

const usableBoundary = (shape: PickerShape) => (shape.problems.length ? null : shape.boundary)

/**
 * Meters from each shape to the field's system: from the nearest point of its edge, 0 where they
 * overlap (systemDistanceM); null for one that can't be saved. Worked out once for a file's shapes,
 * not again when the names come from another attribute.
 */
export function shapeDistances(shapes: PickerShape[], system: ImportSystem): (number | null)[] {
  return shapes.map((shape) => {
    const boundary = usableBoundary(shape)
    return boundary ? systemDistanceM(boundary, system) : null
  })
}

/**
 * The shapes as rows for the picker: those that can be saved first, the field's name match, then
 * the nearest its system (in the file's order for the same distance); then those that can't be saved
 */
export function pickerRows(
  shapes: PickerShape[],
  nameKey: string | null,
  context: PickerContext,
  distances: (number | null)[] = shapeDistances(shapes, context.system),
): PickerRow[] {
  const { field, system, otherFields } = context
  const asField = [{ id: field.id, name: field.name, pivot_id: field.pivot_id }]
  const rows = shapes.map((shape, index): PickerRow => {
    const name = shapeName(shape, nameKey)
    const boundary = usableBoundary(shape)
    if (!boundary) return { index, shape, name, usable: false, match: null, meters: null, usedBy: null }
    const match = matchField(name, asField, system.id) !== null ? 'name' : null
    const usedBy =
      field.boundary && sameBoundary(boundary, field.boundary)
        ? 'this field'
        : (otherFields.find((other) => sameBoundary(boundary, other.boundary))?.name ?? null)
    return { index, shape, name, usable: true, match, meters: distances[index], usedBy }
  })
  const rank = (row: PickerRow) => (!row.usable ? 2 : row.match === 'name' ? 0 : 1)
  return rows.toSorted((a, b) => rank(a) - rank(b) || (a.meters ?? 0) - (b.meters ?? 0) || a.index - b.index)
}

/** Whose shape it already is ("Used for East 40"), or null */
const usedNote = (row: PickerRow) =>
  row.usedBy === 'this field' ? "This field's shape now" : row.usedBy ? `Used for ${row.usedBy}` : null

/**
 * What the expanded picker's Notes say of a shape: why it can't be saved; or that its name is the
 * field's, whose shape it already is, and what reading it changed
 */
export function rowNotes(row: PickerRow): string[] {
  if (!row.usable) return [`This shape ${row.shape.problems.join('; ')}`]
  const notes: string[] = []
  if (row.match === 'name') notes.push('Best match: same name')
  const used = usedNote(row)
  if (used) notes.push(used)
  const changed = shapeNotes(row.shape)
  if (changed) notes.push(changed)
  return notes
}

/** The compact picker's line under a shape's name: why it can't be saved, or whose shape it already is */
export function rowTag(row: PickerRow): string | null {
  return row.usable ? usedNote(row) : rowNotes(row)[0]
}

/** Every attribute in the shapes, in the order first seen */
export function attributeKeys(shapes: { properties: Record<string, unknown> }[]): string[] {
  const keys = new Set<string>()
  for (const shape of shapes) for (const key of Object.keys(shape.properties)) keys.add(key)
  return [...keys]
}

/** An attribute's value for a table cell and its sorting: text, a number, or null */
export function attributeValue(value: unknown): string | number | null {
  if (value === null || value === undefined || value === '') return null
  if (typeof value === 'number' || typeof value === 'string') return value
  if (typeof value === 'boolean') return value ? 'Yes' : 'No'
  return JSON.stringify(value)
}

// A problem's verb for several shapes ("is too small" → "are too small")
const PLURAL_VERBS: [string, string][] = [
  ['is ', 'are '],
  ["isn't ", "aren't "],
  ['has ', 'have '],
  ['crosses itself', 'cross themselves'],
]
const plural = (problem: string) => {
  const verb = PLURAL_VERBS.find(([one]) => problem.startsWith(one))
  return verb ? verb[1] + problem.slice(verb[0].length) : problem
}

/**
 * Why shapes can't be saved, the commonest first: "2,948 are larger than a field (at most 1,500
 * acres); 1 must be in the US or Canada"
 */
export function unusableSummary(shapes: { problems: string[] }[]): string {
  const counts = new Map<string, number>()
  for (const shape of shapes) for (const problem of shape.problems) counts.set(problem, (counts.get(problem) ?? 0) + 1)
  return [...counts]
    .sort((a, b) => b[1] - a[1])
    .map(([problem, count]) => `${count.toLocaleString('en-US')} ${count === 1 ? problem : plural(problem)}`)
    .join('; ')
}
