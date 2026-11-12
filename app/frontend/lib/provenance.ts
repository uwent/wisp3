import type { FieldDay } from '@/types/serializers'

export type Source = FieldDay['rain_source']

// How each input's source is named in the grid, chart tooltips and badges (PLAN.md §4 provenance)
export const SOURCE_LABELS: Record<Source, string> = {
  entered: 'entered',
  // A part-field planting's irrigation entered for its whole field (PLAN.md Phase 8 G.11)
  field: 'from field',
  pivot: 'from pivot',
  model: 'modeled',
  forecast: 'forecast',
  none: 'none',
  missing: 'missing',
}

export const ET_SOURCE_LABELS: Record<FieldDay['et_source'], string> = {
  computed: 'computed',
  gap_fill: 'estimated (no weather)',
  missing: 'missing',
}

/** True when the grower's entered rain replaced the modeled rain */
export const rainOverridden = (day: Pick<FieldDay, 'rain_source' | 'rain_model'>) =>
  day.rain_source === 'entered' && day.rain_model !== null
