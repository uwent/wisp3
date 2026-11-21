import { render, screen } from '@testing-library/svelte'
import { flushSync } from 'svelte'
import { beforeEach, describe, expect, it, vi } from 'vitest'

import { form } from '@/test/FakeForm.svelte'
vi.mock('@inertiajs/svelte', async () => ({
  ...(await import('@/test/page.svelte')),
  Form: (await import('@/test/FakeForm.svelte')).default,
}))

import type { Field, GenericCurve, Plant, Planting } from '@/types/serializers'
import PlantingForm from './PlantingForm.svelte'

const corn: Plant = {
  id: 1,
  key: 'corn',
  name: 'Corn',
  default_max_root_zone_depth: 36,
  has_lai_curve: false,
  has_cover_curve: true,
  has_vine_kill: false,
  season_days: 120,
  default_generic_curve: null,
}
const kale: Plant = {
  ...corn,
  id: 2,
  key: 'kale',
  name: 'Kale',
  has_cover_curve: false,
  default_generic_curve: 'leafy',
}
const curves = [{ key: 'leafy', name: 'Leafy greens', basis: 'Lettuce', season_days: 60 }] as GenericCurve[]

const field = {
  id: 7,
  name: 'North 40',
  area_acres: 40,
  soil_type_id: 3,
  soil_type_name: 'Silt loam',
  plantings: [],
  boundary: null,
} as unknown as Field

const plantingOf = (plant: Plant, extra: Partial<Planting> = {}) =>
  ({
    id: 11,
    field_id: field.id,
    plant_id: plant.id,
    plant_name: plant.name,
    season_start: '2026-04-01',
    emergence_date: '2026-05-01',
    end_date: '2026-09-30',
    vine_kill_date: null,
    max_root_zone_depth: 36,
    mad_frac: 0.5,
    et_method: 'pct_cover',
    canopy_interpolation: 'curve',
    target_ad_pct: null,
    initial_moisture_pct: null,
    partial: true,
    plot_length_ft: null,
    plot_width_ft: null,
    area_acres: 10,
    own_soil: false,
    canopy_curve_key: null,
    season_days: null,
    ended: false,
    ...extra,
  }) as unknown as Planting

function show(planting: Planting, errors: Record<string, string>) {
  form.errors = errors
  render(PlantingForm, {
    planting,
    field,
    year: 2026,
    plants: [corn, kale],
    genericCurves: curves,
    ondone: () => {},
  })
  flushSync()
}

describe('PlantingForm errors', () => {
  beforeEach(() => {
    form.errors = {}
  })

  it('shows the size, canopy method and interpolation errors by their controls, opening Settings', () => {
    show(plantingOf(corn), {
      partial: "Planting size can't change to the whole field while this planting has its own irrigation or readings",
      et_method: 'Canopy method can be LAI (leaf area index) only for crops that have an LAI growth curve (none yet)',
      canopy_interpolation: 'Canopy interpolation is not included in the list',
    })
    const size = screen.getByRole('group', { name: 'Planting size' })
    expect(size).toHaveTextContent("Planting size can't change to the whole field")
    expect(screen.getByRole('group', { name: 'Canopy method' })).toHaveTextContent('can be LAI (leaf area index) only')
    expect(screen.getByRole('group', { name: 'Between canopy readings' })).toHaveTextContent(
      'Canopy interpolation is not included in the list',
    )
    expect(document.querySelector('details')!.open).toBe(true)
  })

  it("shows a generic curve's error with the curves", () => {
    show(plantingOf(kale), { canopy_curve_key: "Canopy curve key isn't a canopy curve WISP has" })
    expect(screen.getByRole('group', { name: 'Canopy curve' })).toHaveTextContent("isn't a canopy curve WISP has")
  })

  it('lists errors without a control on the form at its end, once each', () => {
    show(plantingOf(corn), {
      base: 'Something went wrong',
      field: 'Field must exist',
      canopy_curve_key: 'Canopy curve key can be chosen only for crops without their own canopy curve',
      area_acres: 'Area must be greater than 0',
    })
    expect(screen.getByText('Something went wrong')).toBeInTheDocument()
    expect(screen.getByText('Field must exist')).toBeInTheDocument()
    expect(screen.getByText(/can be chosen only for crops without their own canopy curve/)).toBeInTheDocument()
    // Area has its box (part of the field), so it's shown there only
    expect(screen.getAllByText('Area must be greater than 0')).toHaveLength(1)
  })
})
