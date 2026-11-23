import { fireEvent, render, screen } from '@testing-library/svelte'
import { describe, expect, it, vi } from 'vitest'

vi.mock('@inertiajs/svelte', async () => ({
  ...(await import('@/test/page.svelte')),
  Form: (await import('@/test/FakeForm.svelte')).default,
  Link: (await import('@/test/FakeLink.svelte')).default,
  router: { on: () => () => {} },
}))

import type { WeekFarm } from '@/lib/dailyWeek'

import Week from './Week.svelte'

const dates = ['2026-07-14', '2026-07-15', '2026-07-16', '2026-07-17', '2026-07-18', '2026-07-19', '2026-07-20']
const fields = [
  { id: 1, name: 'North', value: null },
  { id: 2, name: 'South', value: null },
]
const farms: WeekFarm[] = [
  {
    id: 1,
    name: 'Home',
    rain_rows: [
      {
        key: 'group-3',
        name: 'East',
        kind: 'group',
        systems: 1,
        days: dates.map((date) =>
          date === '2026-07-17'
            ? {
                active: true,
                value: null,
                varies: true,
                fields: [
                  { id: 1, name: 'North', value: 0.4 },
                  { id: 2, name: 'South', value: 0.6 },
                ],
              }
            : { active: date !== '2026-07-14', value: null, varies: false, fields },
        ),
      },
    ],
    irrigation_rows: [
      {
        key: 'system-12',
        id: 12,
        name: 'River',
        kind: 'center',
        kind_name: 'Pivot',
        pump_capacity_gpm: null,
        inches_at_100: null,
        days: dates.map((date) =>
          date === '2026-07-15'
            ? {
                active: true,
                value: null,
                varies: true,
                fields: [
                  { id: 1, name: 'North', value: 0.6 },
                  { id: 2, name: 'South', value: null },
                ],
              }
            : { active: true, value: null, varies: false, fields },
        ),
      },
    ],
  },
]

const hidden = (container: HTMLElement) =>
  [...container.querySelectorAll<HTMLInputElement>('input[type="hidden"]')].map((input) => [input.name, input.value])

describe('the week grid', () => {
  it('submits only the cells changed, marking a varied cell typed over', async () => {
    const { container } = render(Week, { date: '2026-07-20', dates, farms, has_systems: true })
    expect(screen.getByLabelText('East rain, Tue, Jul 14')).toBeDisabled()
    expect(hidden(container)).toEqual([['date', '2026-07-20']])

    const varied = screen.getByLabelText('East rain, Fri, Jul 17')
    expect(varied).toHaveAttribute('placeholder', 'varies')
    await fireEvent.input(varied, { target: { value: '0.5' } })
    expect(varied).toHaveAccessibleDescription(/^Replaces different amounts: North 0.40 in, South 0.60 in$/)
    expect(hidden(container)).toEqual([
      ['date', '2026-07-20'],
      ['days[2026-07-17][fields][1][rain_in]', '0.5'],
      ['days[2026-07-17][fields][2][rain_in]', '0.5'],
    ])

    const partial = screen.getByLabelText('River irrigation, Wed, Jul 15')
    expect(partial).toHaveValue('')
    expect(partial).toHaveAttribute('placeholder', 'varies')
    await fireEvent.input(partial, { target: { value: '0.7' } })
    expect(partial).toHaveAccessibleDescription(/^Replaces different amounts: North 0.60 in, South —$/)
    expect(hidden(container).slice(3)).toEqual([
      ['days[2026-07-15][fields][1][irrigation_in]', '0.7'],
      ['days[2026-07-15][fields][2][irrigation_in]', '0.7'],
    ])
  })

  it('moves between cells with the arrow keys and Enter, past those taking no value', async () => {
    render(Week, { date: '2026-07-20', dates, farms, has_systems: true })
    const first = screen.getByLabelText('East rain, Wed, Jul 15') as HTMLInputElement
    first.focus()
    await fireEvent.keyDown(first, { key: 'ArrowLeft' })
    expect(document.activeElement).toBe(first) // Jul 14 takes no rain
    await fireEvent.keyDown(first, { key: 'Enter' })
    expect(document.activeElement).toBe(screen.getByLabelText('River irrigation, Wed, Jul 15'))
  })
})
