// The name and crop search on the dashboard, Setup and the map's list: text matched (any case)
// in a farm's, irrigation group's, system's or field's name, or a field's crops and varieties. A
// match keeps everything under it, and its parents.

type Crop = { plant_name: string; variety: string | null }
type SearchField = { name: string; plantings: Crop[] }
type SearchSystem<F extends SearchField> = { name: string; pivot_group_id: number | null; fields: F[] }
type SearchFarm<F extends SearchField, S extends SearchSystem<F>> = {
  name: string
  pivot_groups: { id: number; name: string }[]
  pivots: S[]
}

/** The query as matched: trimmed and lower case; '' matches everything */
export const searchText = (query: string) => query.trim().toLowerCase()

const has = (name: string | null | undefined, text: string) => name != null && name.toLowerCase().includes(text)

/** Whether a field's name, or one of its crops or varieties (crops: the plantings to look at), contains text */
export function fieldMatches<F extends SearchField>(
  field: F,
  text: string,
  crops: (field: F) => Crop[] = (f) => f.plantings,
) {
  return (
    !text || has(field.name, text) || crops(field).some((crop) => has(crop.plant_name, text) || has(crop.variety, text))
  )
}

/**
 * The farms with only what the query matches: a farm, group or system matching keeps all its
 * fields; otherwise the fields matching, and the systems and farms left with any. crops: a field's
 * plantings to match (Setup's season); all of them by default. A farm keeps only the irrigation
 * groups left with a system.
 */
export function searchFarms<F extends SearchField, S extends SearchSystem<F>, R extends SearchFarm<F, S>>(
  farms: R[],
  query: string,
  crops?: (field: F) => Crop[],
): R[] {
  const text = searchText(query)
  if (!text) return farms
  return farms.flatMap((farm) => {
    if (has(farm.name, text)) return [farm]
    const groups = new Set(farm.pivot_groups.filter((group) => has(group.name, text)).map((group) => group.id))
    const pivots = farm.pivots.flatMap((pivot) => {
      if (has(pivot.name, text) || (pivot.pivot_group_id !== null && groups.has(pivot.pivot_group_id))) return [pivot]
      const fields = pivot.fields.filter((field) => fieldMatches(field, text, crops))
      return fields.length ? [{ ...pivot, fields }] : []
    })
    if (!pivots.length) return []
    // The groups left with a system, or matching themselves
    const kept = farm.pivot_groups.filter(
      (group) => groups.has(group.id) || pivots.some((pivot) => pivot.pivot_group_id === group.id),
    )
    return [{ ...farm, pivots, pivot_groups: kept }]
  })
}
