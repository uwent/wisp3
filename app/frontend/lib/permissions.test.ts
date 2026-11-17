import { describe, expect, it } from 'vitest'

import { mayDelete } from './permissions'
import type { SharedProps } from '@/types'

const auth = (owner: boolean, userId = 7) =>
  ({ owner, user: { id: userId }, group: null, groups: [], impersonator: null }) as unknown as SharedProps['auth']

describe('mayDelete', () => {
  it('lets owners delete anything, and members what they added', () => {
    expect(mayDelete({ created_by_id: null }, auth(true))).toBe(true)
    expect(mayDelete({ created_by_id: 7 }, auth(false))).toBe(true)
    expect(mayDelete({ created_by_id: 8 }, auth(false))).toBe(false)
    // Made before creators were recorded: owners only
    expect(mayDelete({ created_by_id: null }, auth(false))).toBe(false)
  })
})
