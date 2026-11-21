import { fireEvent, render, screen, within } from '@testing-library/svelte'
import { describe, expect, it, vi } from 'vitest'

vi.mock('@inertiajs/svelte', () => import('@/test/page.svelte'))
// DataTable measures its pinned headings, which jsdom can't
vi.stubGlobal(
  'ResizeObserver',
  class {
    observe() {}
    unobserve() {}
    disconnect() {}
  },
)

import type { Boundary } from '@/lib/boundary'
import type { LngLat } from '@/lib/geo'

import type { PickerContext, PickerShape } from './picker'
import ShapePicker from './ShapePicker.svelte'

const squareAt = (lng: number, lat: number): Boundary => ({
  type: 'Polygon',
  coordinates: [
    [
      [lng, lat],
      [lng + 0.01, lat],
      [lng + 0.01, lat + 0.01],
      [lng, lat + 0.01],
      [lng, lat],
    ] as LngLat[],
  ],
})
const usable = (name: string, id: string, lng: number): PickerShape => ({
  properties: { FIELD_NAME: name, CLU: id },
  boundary: squareAt(lng, 43),
  acres: 190,
  notes: [],
  problems: [],
})
const county: PickerShape = {
  properties: { FIELD_NAME: 'Dane', CLU: 'C1' },
  boundary: null,
  acres: 790000,
  notes: [],
  problems: ['is larger than a field (at most 1,500 acres)'],
}
const context: PickerContext = {
  field: { id: 1, name: 'Home South', pivot_id: 5, boundary: null },
  system: {
    id: 5,
    name: 'Pivot 1',
    kind: 'center',
    latitude: 44.1,
    longitude: -89.5,
    radius_ft: 1320,
    arc_start_deg: null,
    arc_end_deg: null,
    length_ft: null,
    travel_ft: null,
    travel_bearing_deg: null,
  },
  otherFields: [],
}

const renderPicker = (onpick = vi.fn()) =>
  render(ShapePicker, {
    props: {
      shapes: [usable('Home North', '12', -88), county, usable('Home South', '13', -88.1)],
      fileName: 'Fields.zip',
      nameKey: 'FIELD_NAME',
      context,
      systemLabel: 'Pivot 1 (center pivot)',
      onpick,
      onforget: vi.fn(),
    },
  })

const table = () => screen.getByRole('table', { name: 'Shapes from Fields.zip' })
const nameButtons = () =>
  within(table())
    .queryAllByRole('button')
    .filter((button) => !button.closest('th'))
    .map((button) => button.textContent)

describe('ShapePicker', () => {
  it("lists the shapes that can be saved, the field's name first, and picks one", async () => {
    const onpick = vi.fn()
    renderPicker(onpick)
    expect(screen.getByRole('heading', { name: 'Shapes from Fields.zip: pick one for Home South' })).toBeInTheDocument()
    expect(nameButtons()).toEqual(['Home South', 'Home North'])
    expect(within(table()).getByText('Best match: same name')).toBeInTheDocument()
    expect(within(table()).queryByText('Dane')).toBeNull()

    await fireEvent.click(within(table()).getByRole('button', { name: 'Home South' }))
    expect(onpick).toHaveBeenCalledWith(
      expect.objectContaining({ properties: { FIELD_NAME: 'Home South', CLU: '13' } }),
    )
  })

  it("shows those that can't be used when asked, with why, not to be picked", async () => {
    renderPicker()
    await fireEvent.click(screen.getByLabelText("Show the 1 that can't be used"))
    expect(within(table()).getByText('Dane')).toBeInTheDocument()
    expect(within(table()).queryByRole('button', { name: 'Dane' })).toBeNull()
    expect(within(table()).getByText('This shape is larger than a field (at most 1,500 acres)')).toBeInTheDocument()
  })

  it('names the shapes from another attribute', async () => {
    renderPicker()
    await fireEvent.change(screen.getByLabelText('Names from'), { target: { value: 'CLU' } })
    expect(nameButtons()).toEqual(['12', '13'])
    expect(within(table()).getByRole('columnheader', { name: /^CLU/ })).toBeInTheDocument()
    expect(within(table()).getByRole('columnheader', { name: /^FIELD_NAME/ })).toBeInTheDocument()
  })
})
