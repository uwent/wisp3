import { fireEvent, render, screen } from '@testing-library/svelte'
import { describe, expect, it, vi } from 'vitest'

vi.mock('@inertiajs/svelte', () => import('@/test/page.svelte'))

import CoordinatesField from './CoordinatesField.svelte'

const hidden = (container: HTMLElement, name: string) =>
  (container.querySelector(`input[name="system[${name}]"]`) as HTMLInputElement).value

describe('CoordinatesField', () => {
  it('reads what is pasted into the two numbers, and writes it the one way once left', async () => {
    const { container } = render(CoordinatesField, { prefix: 'system', latitude: null, longitude: null })
    const box = screen.getByLabelText('Coordinates') as HTMLInputElement

    await fireEvent.input(box, { target: { value: `44°07'24.2"N 89°34'04.1"W` } })
    expect(hidden(container, 'latitude')).toBe('44.123389')
    expect(hidden(container, 'longitude')).toBe('-89.567806')
    expect(box.value).toBe(`44°07'24.2"N 89°34'04.1"W`)

    await fireEvent.blur(box)
    expect(box.value).toBe('44.123389, -89.567806')
  })

  it("says when it read them the other way round, or the place isn't in the US", async () => {
    render(CoordinatesField, { prefix: 'system', latitude: null, longitude: null })
    const box = screen.getByLabelText('Coordinates') as HTMLInputElement

    await fireEvent.input(box, { target: { value: '-89.5, 44.1' } })
    expect(screen.getByText(/Read as longitude, then latitude/)).toBeInTheDocument()

    await fireEvent.input(box, { target: { value: '44.1, 89.5' } })
    expect(screen.getByText(/east of Greenwich/)).toBeInTheDocument()
  })

  it("won't let the form submit what it can't read (the last location read stays in the hidden inputs)", async () => {
    const { container } = render(CoordinatesField, { prefix: 'system', latitude: 44.1, longitude: -89.5 })
    const box = screen.getByLabelText('Coordinates') as HTMLInputElement
    expect(box.value).toBe('44.1, -89.5')

    await fireEvent.input(box, { target: { value: '44.2' } })
    expect(box).toHaveAttribute('aria-invalid', 'true')
    expect(box.validity.valid).toBe(false)
    expect(screen.getByText(/Add the longitude/)).toBeInTheDocument()
    expect(hidden(container, 'latitude')).toBe('44.1')

    await fireEvent.blur(box)
    expect(box.value).toBe('44.2')
    await fireEvent.input(box, { target: { value: '44.2, -89.6' } })
    expect(box.validity.valid).toBe(true)
  })
})
