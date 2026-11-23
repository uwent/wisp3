import { fireEvent, render, screen } from '@testing-library/svelte'
import { describe, expect, it, vi } from 'vitest'

vi.mock('@inertiajs/svelte', () => import('@/test/page.svelte'))

import NumberField from './NumberField.svelte'

describe('NumberField', () => {
  it("won't let the form submit what it can't read (the last number read stays in the hidden input)", async () => {
    render(NumberField, { label: 'Radius', name: 'system[radius_ft]', value: 12 })
    const box = screen.getByLabelText('Radius') as HTMLInputElement
    expect(box.validity.valid).toBe(true)

    await fireEvent.input(box, { target: { value: '12x' } })
    expect(box).toHaveAttribute('aria-invalid', 'true')
    expect(box.validity.valid).toBe(false)

    await fireEvent.input(box, { target: { value: '14' } })
    expect(box.validity.valid).toBe(true)
  })

  it('shows a precision always, and rounds what was typed to it when the box is left', async () => {
    const { container } = render(NumberField, {
      label: 'Rain',
      name: 'rain',
      quantity: 'depth',
      precision: 2,
      value: 1,
    })
    const box = screen.getByLabelText('Rain') as HTMLInputElement
    const hidden = () => (container.querySelector('input[name="rain"]') as HTMLInputElement).value
    expect(box).toHaveValue('1.00')

    await fireEvent.input(box, { target: { value: '0.456' } })
    expect(box).toHaveValue('0.456')
    await fireEvent.blur(box)
    expect(box).toHaveValue('0.46')
    expect(hidden()).toBe('0.46')

    await fireEvent.input(box, { target: { value: '' } })
    await fireEvent.blur(box)
    expect(box).toHaveValue('')
  })

  it("leaves a saved value with more places alone until it's typed over", async () => {
    const { container } = render(NumberField, {
      label: 'Rain',
      name: 'rain',
      quantity: 'depth',
      precision: 2,
      value: 0.177,
    })
    const box = screen.getByLabelText('Rain') as HTMLInputElement
    expect(box).toHaveValue('0.18')
    await fireEvent.focus(box)
    await fireEvent.blur(box)
    expect((container.querySelector('input[name="rain"]') as HTMLInputElement).value).toBe('0.177')
  })
})
