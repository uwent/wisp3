// Searching and sorting rows for DataTable, kept pure for testing

export type SortValue = string | number | boolean | null | undefined
export type SortDirection = 'asc' | 'desc'

/** A DataTable column: value sorts it; what it shows (text, or else value) is what search matches */
export type Column<Row> = {
  key: string
  label: string
  value: (row: Row) => SortValue
  text?: (row: Row) => string
  align?: 'left' | 'right' | 'center'
  searchable?: boolean
  sortable?: boolean
  /** The first click sorts this way (e.g. newest or largest first) */
  firstDirection?: SortDirection
}

/** What a cell shows: its text, or its value; blank when missing */
export const cellText = <Row>(column: Column<Row>, row: Row): string => {
  const shown = column.text ? column.text(row) : column.value(row)
  return shown === null || shown === undefined ? '' : String(shown)
}

/** Rows ordered by value; missing values (null, undefined, '') go last in either direction */
export function sortRows<T>(rows: T[], value: (row: T) => SortValue, direction: SortDirection): T[] {
  const sign = direction === 'asc' ? 1 : -1
  const missing = (v: SortValue) => v === null || v === undefined || v === ''
  return rows.toSorted((a, b) => {
    const [x, y] = [value(a), value(b)]
    if (missing(x) || missing(y)) return Number(missing(x)) - Number(missing(y))
    if (typeof x === 'string' && typeof y === 'string')
      return sign * x.localeCompare(y, undefined, { numeric: true, sensitivity: 'base' })
    return sign * (Number(x) - Number(y))
  })
}

/** True when every word of the query appears in one of the texts, ignoring case */
export function matchesQuery(query: string, texts: SortValue[]): boolean {
  const words = query.toLowerCase().split(/\s+/).filter(Boolean)
  const haystack = texts
    .filter((text) => text !== null && text !== undefined)
    .join(' ')
    .toLowerCase()
  return words.every((word) => haystack.includes(word))
}
