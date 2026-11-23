// The name and crop search on the dashboard, Setup and the map's list: text matched (any case)
// in a farm's, irrigation group's, system's or field's name, or a field's crops and varieties. A
// match keeps everything under it, and its parents.

type Crop = { plant_name: string; variety: string | null }
type SearchField = { name: string; plantings: Crop[] }
type SearchSystem<F extends SearchField> = { name: string; irrigation_group_id: number | null; fields: F[] }
type SearchFarm<F extends SearchField, S extends SearchSystem<F>> = {
  name: string
  irrigation_groups: { id: number; name: string }[]
  systems: S[]
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
    const groups = new Set(farm.irrigation_groups.filter((group) => has(group.name, text)).map((group) => group.id))
    const systems = farm.systems.flatMap((system) => {
      if (has(system.name, text) || (system.irrigation_group_id !== null && groups.has(system.irrigation_group_id)))
        return [system]
      const fields = system.fields.filter((field) => fieldMatches(field, text, crops))
      return fields.length ? [{ ...system, fields }] : []
    })
    if (!systems.length) return []
    // The groups left with a system, or matching themselves
    const kept = farm.irrigation_groups.filter(
      (group) => groups.has(group.id) || systems.some((system) => system.irrigation_group_id === group.id),
    )
    return [{ ...farm, systems, irrigation_groups: kept }]
  })
}
