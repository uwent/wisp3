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
  field: { id: 1, name: 'Home South', system_id: 5, boundary: null },
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

const renderPicker = (props: Record<string, unknown> = {}) =>
  render(ShapePicker, {
    props: {
      shapes: [usable('Home North', '12', -88), county, usable('Home South', '13', -88.1)],
      fileName: 'Fields.zip',
      nameKey: 'FIELD_NAME',
      context,
      systemLabel: 'Pivot 1 (center pivot)',
      onpick: vi.fn(),
      onclose: vi.fn(),
      onchoose: vi.fn(),
      onforget: vi.fn(),
      ...props,
    },
  })

const table = () => screen.getByRole('table', { name: 'Shapes from Fields.zip' })
const expandedTable = () => screen.getByRole('table', { name: 'All of the shapes from Fields.zip' })
const nameButtons = (within_ = table()) =>
  within(within_)
    .queryAllByRole('button')
    .filter((button) => !button.closest('th'))
    .map((button) => button.textContent)
const headings = (within_: HTMLElement) =>
  within(within_)
    .getAllByRole('columnheader')
    .map((th) => th.textContent?.replace(/[▴▾]/g, '').trim())

describe('ShapePicker', () => {
  it("lists the shapes that can be saved by name, area and distance, the field's name first, and picks one", async () => {
    const onpick = vi.fn()
    renderPicker({ onpick })
    expect(screen.getByRole('heading', { name: 'Field import' })).toBeInTheDocument()
    expect(
      screen.getByText(
        "Loaded 3 shapes from Fields.zip. 1 can't be used for a field. Sort or search to find your field.",
      ),
    ).toBeInTheDocument()
    expect(headings(table())).toEqual(['Name', 'Area', 'Distance'])
    expect(nameButtons()).toEqual(['Home South', 'Home North'])
    expect(within(table()).queryByText('Dane')).toBeNull()
    // About 113 km from the system, as miles
    expect(within(table()).getAllByText(/^\d+\.\d mi$/)).toHaveLength(2)

    await fireEvent.click(within(table()).getByRole('button', { name: 'Home South' }))
    expect(onpick).toHaveBeenCalledWith(
      expect.objectContaining({ properties: { FIELD_NAME: 'Home South', CLU: '13' } }),
    )
  })

  it("searches the attributes it doesn't show", async () => {
    renderPicker()
    await fireEvent.input(screen.getByRole('searchbox', { name: 'Search the shapes' }), { target: { value: '12' } })
    expect(nameButtons()).toEqual(['Home North'])
  })

  it('marks the shape on the map now', () => {
    renderPicker({ current: usable('Home North', '12', -88).boundary })
    expect(within(table()).getByRole('button', { name: 'Home North' })).toHaveAttribute('aria-current', 'true')
    expect(within(table()).getByRole('button', { name: 'Home South' })).not.toHaveAttribute('aria-current')
  })

  it("expands to every attribute and the notes, with those that can't be used when asked, not to be picked", async () => {
    const onpick = vi.fn()
    renderPicker({ onpick })
    await fireEvent.click(screen.getByRole('button', { name: 'Expand the table' }))
    expect(headings(expandedTable())).toEqual(['Name', 'Area', 'Distance', 'Notes', 'CLU'])
    expect(within(expandedTable()).getByText('Best match: same name')).toBeInTheDocument()

    await fireEvent.click(screen.getByLabelText("Show the 1 that can't be used"))
    expect(within(expandedTable()).getByText('Dane')).toBeInTheDocument()
    expect(within(expandedTable()).queryByRole('button', { name: 'Dane' })).toBeNull()
    expect(
      within(expandedTable()).getByText('This shape is larger than a field (at most 1,500 acres)'),
    ).toBeInTheDocument()

    await fireEvent.click(within(expandedTable()).getByRole('button', { name: 'Home North' }))
    expect(onpick).toHaveBeenCalledWith(
      expect.objectContaining({ properties: { FIELD_NAME: 'Home North', CLU: '12' } }),
    )
  })

  it('names the shapes from another attribute', async () => {
    renderPicker()
    await fireEvent.change(screen.getByLabelText('Names from', { exact: true }), { target: { value: 'CLU' } })
    // No name is the field's now, so the nearest its system comes first
    expect(nameButtons()).toEqual(['13', '12'])
  })

  it('closes, reads another file, or forgets the shapes', async () => {
    const [onclose, onchoose, onforget] = [vi.fn(), vi.fn(), vi.fn()]
    renderPicker({ onclose, onchoose, onforget })
    await fireEvent.click(screen.getByRole('button', { name: 'Close the field import' }))
    await fireEvent.click(screen.getByRole('button', { name: 'Choose another file' }))
    await fireEvent.click(screen.getByRole('button', { name: 'Forget these shapes' }))
    expect([onclose, onchoose, onforget].map((fn) => fn.mock.calls.length)).toEqual([1, 1, 1])
  })
})
