import type { FieldDay } from '@/types/serializers'

export type Source = FieldDay['rain_source']

// How each input's source is named in the grid, chart tooltips and badges (PLAN.md §4 provenance)
export const SOURCE_LABELS: Record<Source, string> = {
  entered: 'entered',
  pivot: 'from pivot',
  group: 'field group',
  model: 'modeled',
  none: 'none',
  missing: 'missing',
}

export const ET_SOURCE_LABELS: Record<FieldDay['et_source'], string> = {
  computed: 'computed',
  gap_fill: 'estimated (no weather)',
  missing: 'missing',
}

/** True when a grower's value (field or field group entry) replaced the modeled rain */
export const rainOverridden = (day: Pick<FieldDay, 'rain_source' | 'rain_model'>) =>
  (day.rain_source === 'entered' || day.rain_source === 'group') && day.rain_model !== null
