import { fireEvent, render, screen } from '@testing-library/svelte'
import { describe, expect, it, vi } from 'vitest'

vi.mock('@inertiajs/svelte', () => import('@/test/page.svelte'))

import NumberField from './NumberField.svelte'

describe('NumberField', () => {
  it("won't let the form submit what it can't read (the last number read stays in the hidden input)", async () => {
    render(NumberField, { label: 'Radius', name: 'pivot[radius_ft]', value: 12 })
    const box = screen.getByLabelText('Radius') as HTMLInputElement
    expect(box.validity.valid).toBe(true)

    await fireEvent.input(box, { target: { value: '12x' } })
    expect(box).toHaveAttribute('aria-invalid', 'true')
    expect(box.validity.valid).toBe(false)

    await fireEvent.input(box, { target: { value: '14' } })
    expect(box.validity.valid).toBe(true)
  })
})
