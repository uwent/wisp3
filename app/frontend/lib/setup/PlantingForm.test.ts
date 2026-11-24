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

describe('PlantingForm last choices', () => {
  beforeEach(() => {
    form.errors = {}
    sessionStorage.clear()
  })

  const showNew = (template?: Partial<Planting>) => {
    render(PlantingForm, { field, year: 2026, plants: [corn, kale], genericCurves: curves, template, ondone: () => {} })
    flushSync()
  }

  it("starts a new planting from this session's last crop and dates, for the same season", () => {
    sessionStorage.setItem(
      'setup.lastPlanting',
      JSON.stringify({ plant_id: 2, season_start: '2026-04-20', emergence_date: '2026-05-12', end_date: '2026-07-15' }),
    )
    showNew()
    expect(screen.getByRole('combobox', { name: /Crop/ })).toHaveValue('2')
    expect(screen.getByText('As your last planting')).toBeInTheDocument()
    expect(document.getElementById('planting-season_start')).toHaveValue('2026-04-20')
    expect(document.getElementById('planting-emergence_date')).toHaveValue('2026-05-12')
    expect(document.getElementById('planting-end_date')).toHaveValue('2026-07-15')
  })

  it('leaves the next planting to its template', () => {
    sessionStorage.setItem(
      'setup.lastPlanting',
      JSON.stringify({ plant_id: 2, season_start: '2026-04-20', emergence_date: '2026-05-12', end_date: '2026-07-15' }),
    )
    showNew({ season_start: '2026-08-01', emergence_date: '2026-08-10', end_date: '2026-10-30' })
    expect(screen.getByRole('combobox', { name: /Crop/ })).toHaveValue('')
  })
})

describe('PlantingForm also plant this on', () => {
  beforeEach(() => {
    form.errors = {}
    sessionStorage.clear()
  })

  const whole = (id: number, season_start: string, end_date: string, partial = false) =>
    ({ id, plant_name: 'Soybean', variety: null, season_start, end_date, partial }) as unknown as Planting
  const east = { ...field, id: 8, name: 'East 40', plantings: [whole(21, '2026-04-01', '2026-06-30')] } as Field
  const west = { ...field, id: 9, name: 'West 40', plantings: [] } as unknown as Field
  const plotted = { ...field, id: 10, name: 'Plots', plantings: [whole(22, '2026-05-01', '2026-09-30', true)] } as Field
  const systemFields = [field, east, west, plotted]

  const showNew = (extra: Record<string, unknown> = {}) => {
    sessionStorage.setItem(
      'setup.lastPlanting',
      JSON.stringify({ plant_id: 1, season_start: '2026-04-15', emergence_date: '2026-05-01', end_date: '2026-09-15' }),
    )
    render(PlantingForm, { field, year: 2026, plants: [corn], systemFields, ondone: () => {}, ...extra })
    flushSync()
  }
  const checkboxNames = () =>
    [...document.querySelectorAll<HTMLInputElement>('input[name="also_field_ids[]"]')].map((box) =>
      box
        .closest('label')!
        .textContent!.replace(/\s*\(.*\)/, '')
        .trim(),
    )
  const setDate = (id: string, value: string) => {
    const input = document.getElementById(id) as HTMLInputElement
    input.value = value
    input.dispatchEvent(new Event('input', { bubbles: true }))
    flushSync()
  }

  it("offers a new whole-field planting the system's other fields free for its dates, as they change", () => {
    showNew()
    expect(screen.getByText('Also plant this on')).toBeInTheDocument()
    // A field growing only plots is free: the planting can cover it with them (D19)
    expect(screen.getByText('2 other fields free')).toBeInTheDocument()
    expect(checkboxNames()).toEqual(['West 40', 'Plots'])

    setDate('planting-season_start', '2026-07-01')
    expect(screen.getByText('3 other fields free')).toBeInTheDocument()
    expect(checkboxNames()).toEqual(['East 40', 'West 40', 'Plots'])
  })

  it('counts the fields chosen, and says so when none is free', () => {
    showNew()
    screen.getByRole('checkbox', { name: /West 40/ }).click()
    flushSync()
    expect(screen.getByText('1 of 2 chosen')).toBeInTheDocument()
    document.body.innerHTML = ''

    showNew({ systemFields: [field, east] })
    expect(screen.getByText('None free for these dates')).toBeInTheDocument()
    expect(checkboxNames()).toEqual([])
  })

  it('is left out for part of the field (the next planting of a plot too), an edit, and a field alone on its system', () => {
    showNew({
      template: { season_start: '2026-04-15', emergence_date: '2026-05-01', end_date: '2026-09-15', partial: true },
    })
    const crop = screen.getByRole('combobox', { name: /Crop/ }) as HTMLSelectElement
    crop.value = '1'
    crop.dispatchEvent(new Event('change', { bubbles: true }))
    flushSync()
    expect(screen.getByRole('group', { name: 'Planting size' })).toBeInTheDocument()
    expect(screen.queryByText('Also plant this on')).not.toBeInTheDocument()
    screen.getByRole('radio', { name: /Whole field/ }).click()
    flushSync()
    expect(screen.getByText('Also plant this on')).toBeInTheDocument()
    document.body.innerHTML = ''

    showNew({ planting: plantingOf(corn, { partial: false, area_acres: 40 }) })
    expect(screen.queryByText('Also plant this on')).not.toBeInTheDocument()
    document.body.innerHTML = ''

    showNew({ systemFields: [field] })
    expect(screen.queryByText('Also plant this on')).not.toBeInTheDocument()
  })

  it("shows the other fields' errors with their list, opening it", () => {
    form.errors = { 'also.9.season_start': 'West 40: overlaps its Soybean planting' }
    showNew()
    const details = screen.getByText('Also plant this on').closest('details')!
    expect(details.open).toBe(true)
    expect(details).toHaveTextContent('West 40: overlaps its Soybean planting')
    expect(screen.getAllByText('West 40: overlaps its Soybean planting')).toHaveLength(1)
  })
})

describe('PlantingForm water', () => {
  beforeEach(() => {
    form.errors = {}
    sessionStorage.clear()
  })

  const water = () => screen.getByRole('group', { name: /^Water/ })
  const checked = (name: RegExp) => (screen.getByRole('radio', { name }) as HTMLInputElement).checked

  it('starts a new planting rainfed on a location with no pump', () => {
    render(PlantingForm, {
      field: { ...field, rainfed_default: true } as Field,
      year: 2026,
      plants: [corn],
      ondone: () => {},
    })
    flushSync()
    const crop = screen.getByRole('combobox', { name: /^Crop/ })
    ;(crop as HTMLSelectElement).value = String(corn.id)
    crop.dispatchEvent(new Event('change', { bubbles: true }))
    flushSync()
    expect(water()).toBeInTheDocument()
    expect(checked(/^Rainfed/)).toBe(true)
  })

  it("keeps a planting's own choice, and hides the irrigation target for a rainfed one", () => {
    show(plantingOf(corn, { rainfed: true, target_ad_pct: 40 }), {})
    expect(checked(/^Rainfed/)).toBe(true)
    expect(screen.queryByLabelText(/^Target allowable depletion/)).not.toBeInTheDocument()
    expect(document.querySelector<HTMLInputElement>('input[name="planting[target_ad_pct]"]')!.value).toBe('40')

    screen.getByRole('radio', { name: 'Irrigated' }).click()
    flushSync()
    expect(screen.getByLabelText(/^Target allowable depletion/)).toBeInTheDocument()
  })
})
