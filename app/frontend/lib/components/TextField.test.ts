import { render, screen } from '@testing-library/svelte'
import { describe, expect, it } from 'vitest'

import TextField from './TextField.svelte'

describe('TextField', () => {
  it('labels the input and submits under the given name', () => {
    render(TextField, { label: 'Email', name: 'user[email]', value: 'pat@example.com' })
    const input = screen.getByLabelText('Email')
    expect(input).toHaveAttribute('name', 'user[email]')
    expect(input).toHaveValue('pat@example.com')
  })

  it('shows the first server error and marks the input invalid', () => {
    render(TextField, { label: 'Email', name: 'email', error: ["can't be blank", 'is invalid'], hint: 'ignored' })
    const input = screen.getByLabelText('Email')
    expect(input).toHaveAttribute('aria-invalid', 'true')
    expect(input).toHaveAccessibleDescription("can't be blank")
    expect(screen.queryByText('is invalid')).not.toBeInTheDocument()
  })

  it('shows the hint when there is no error', () => {
    render(TextField, { label: 'Password', name: 'password', hint: 'At least 8 characters' })
    expect(screen.getByLabelText('Password')).toHaveAccessibleDescription('At least 8 characters')
  })
})
