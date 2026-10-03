import { fireEvent, render, screen } from '@testing-library/svelte'
import { createRawSnippet, tick } from 'svelte'
import { describe, expect, it, vi } from 'vitest'

import EditableCell from './EditableCell.svelte'

const children = createRawSnippet(() => ({ render: () => '<span>0.50</span>' }))
const props = (onsave: (text: string) => Promise<string | null>) => ({
  text: '0.5',
  label: 'Rain, Wed, Jul 1',
  grid: 'days',
  row: 0,
  col: 0,
  onsave,
  children,
})

describe('EditableCell', () => {
  it('opens an input on click and saves the edited text on Enter', async () => {
    const onsave = vi.fn().mockResolvedValue(null)
    render(EditableCell, props(onsave))
    await fireEvent.click(screen.getByRole('button', { name: 'Rain, Wed, Jul 1' }))
    const input = screen.getByRole('textbox', { name: 'Rain, Wed, Jul 1' })
    expect(input).toHaveValue('0.5')
    await fireEvent.input(input, { target: { value: '0.8' } })
    await fireEvent.keyDown(input, { key: 'Enter' })
    await vi.waitFor(() => expect(onsave).toHaveBeenCalledWith('0.8'))
    await vi.waitFor(() => expect(screen.getByRole('button')).toHaveTextContent('0.50'))
  })

  it('starts editing with the key typed on a focused cell', async () => {
    render(EditableCell, props(vi.fn().mockResolvedValue(null)))
    await fireEvent.keyDown(screen.getByRole('button'), { key: '7' })
    await tick()
    expect(screen.getByRole('textbox')).toHaveValue('7')
  })

  it("doesn't save unchanged text, and Escape cancels", async () => {
    const onsave = vi.fn()
    render(EditableCell, props(onsave))
    await fireEvent.click(screen.getByRole('button'))
    await fireEvent.keyDown(screen.getByRole('textbox'), { key: 'Enter' })
    await fireEvent.click(screen.getByRole('button'))
    await fireEvent.input(screen.getByRole('textbox'), { target: { value: '3' } })
    await fireEvent.keyDown(screen.getByRole('textbox'), { key: 'Escape' })
    expect(onsave).not.toHaveBeenCalled()
    expect(screen.getByRole('button')).toBeInTheDocument()
  })

  it('keeps the input open and shows the error when saving fails', async () => {
    render(EditableCell, props(vi.fn().mockResolvedValue('Enter a number')))
    await fireEvent.click(screen.getByRole('button'))
    await fireEvent.input(screen.getByRole('textbox'), { target: { value: 'lots' } })
    await fireEvent.keyDown(screen.getByRole('textbox'), { key: 'Enter' })
    expect(await screen.findByRole('alert')).toHaveTextContent('Enter a number')
    expect(screen.getByRole('textbox')).toHaveAttribute('aria-invalid', 'true')
  })
})
