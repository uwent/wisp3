// The fields a system's irrigation can apply to on a date (G.14 part 7), mirroring Pivot#fields_on:
// a field whose season that day ran on the system, or one of its fields with nothing planted then.
// A season keeps the system it ran on, so a field moved away is still on it for its earlier
// seasons, and a field moved here isn't for seasons that ran elsewhere.

export type FieldSeasons = {
  id: number
  name: string
  // On the system now
  here: boolean
  // Its plantings, the one Field#planting_on picks first; dates as ISO strings
  seasons: { from: string; to: string; here: boolean }[]
}

export function fieldsOn<T extends FieldSeasons>(fields: T[], date: string): T[] {
  return fields.filter((field) => {
    const season = field.seasons.find((s) => s.from <= date && date <= s.to)
    return season ? season.here : field.here
  })
}
