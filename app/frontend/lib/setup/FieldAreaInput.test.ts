import { fireEvent, render, screen } from '@testing-library/svelte'
import { describe, expect, it, vi } from 'vitest'

vi.mock('@inertiajs/svelte', () => import('@/test/page.svelte'))

import FieldAreaInput from './FieldAreaInput.svelte'

// A field's area in the dialog and on the shape page (PLAN.md Phase 8 G.14 part 7)
describe('FieldAreaInput', () => {
  const box = () => screen.getByRole('textbox') as HTMLInputElement
  const stored = (container: HTMLElement) => (container.querySelector('input[type=hidden]') as HTMLInputElement).value

  it('shows the area saved beside the box, and copies the shape’s in only when asked', async () => {
    const { container } = render(FieldAreaInput, { name: 'field[area_acres]', value: 20, saved: 20, drawn: 21.534 })
    expect(screen.getByText('Current area').nextElementSibling).toHaveTextContent('20.00 ac')
    expect(screen.getByLabelText('New field area')).toBe(box())
    expect(box().value).toBe('20')
    // Within half an acre: said, not warned
    expect(screen.getByRole('status')).toHaveTextContent('Field as drawn: 21.53 ac, 1.53 ac more than the area above.')
    expect(screen.getByRole('status')).not.toHaveTextContent('Check that')

    await fireEvent.click(screen.getByRole('button', { name: 'Use 21.53 ac' }))
    expect(stored(container)).toBe('21.53')
    expect(screen.getByRole('status')).toHaveTextContent(/^Field as drawn: 21.53 ac\.$/)
    expect(screen.queryByRole('button', { name: /^Use/ })).not.toBeInTheDocument()
  })

  it('warns when the area and the shape’s are far apart', () => {
    render(FieldAreaInput, { name: 'outline[area_acres]', value: 2, saved: 2, drawn: 26.1 })
    expect(screen.getByRole('status')).toHaveTextContent(
      'Field as drawn: 26.10 ac, 24.10 ac more than the area above. Check that the shape covers the whole field',
    )
  })

  it('says None for a field without an area and leaves the box empty', () => {
    render(FieldAreaInput, { name: 'outline[area_acres]', value: null, saved: null, drawn: 12.3 })
    expect(screen.getByText('Current area').nextElementSibling).toHaveTextContent('None')
    expect(box().value).toBe('')
    expect(screen.getByRole('button', { name: 'Use 12.30 ac' })).toBeInTheDocument()
  })

  it('is just the box for a new field', () => {
    render(FieldAreaInput, { name: 'field[area_acres]', value: null })
    expect(screen.getByLabelText('Field area')).toBe(box())
    expect(screen.queryByText('Current area')).not.toBeInTheDocument()
    expect(screen.queryByRole('status')).not.toBeInTheDocument()
  })
})
