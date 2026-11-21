import { describe, expect, it } from 'vitest'

import { count } from './text'

describe('count', () => {
  it('puts the number before the word, plural unless one', () => {
    expect(count(1, 'field')).toBe('1 field')
    expect(count(0, 'field')).toBe('0 fields')
    expect(count(3, 'day')).toBe('3 days')
  })

  it('takes an irregular plural', () => {
    expect(count(1, 'person', 'people')).toBe('1 person')
    expect(count(2, 'person', 'people')).toBe('2 people')
  })

  it('groups thousands', () => {
    expect(count(1200, 'person', 'people')).toBe('1,200 people')
  })
})
