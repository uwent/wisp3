import { describe, expect, it } from 'vitest'

import { insert, link, prefixLines, wrap } from './markdownEdit'

describe('wrap', () => {
  it('wraps the selection and keeps it selected', () => {
    expect(wrap('make this bold', 5, 9, '**', '**', 'bold text')).toEqual({
      text: 'make **this** bold',
      start: 7,
      end: 11,
    })
  })

  it('puts placeholder text in, selected, without a selection', () => {
    expect(wrap('Hi ', 3, 3, '*', '*', 'italic text')).toEqual({ text: 'Hi *italic text*', start: 4, end: 15 })
  })
})

describe('link', () => {
  it('makes the selection a link and selects the address', () => {
    const edit = link('see WISP now', 4, 8)
    expect(edit.text).toBe('see [WISP](https://) now')
    expect(edit.text.slice(edit.start, edit.end)).toBe('https://')
  })
})

describe('prefixLines', () => {
  it('starts every line the selection touches', () => {
    expect(prefixLines('one\ntwo\nthree', 1, 5, '- ').text).toBe('- one\n- two\nthree')
  })

  it('numbers lines', () => {
    expect(prefixLines('one\ntwo', 0, 7, '', true).text).toBe('1. one\n2. two')
  })

  it('takes the prefix off lines that all have it', () => {
    expect(prefixLines('## Title\nmore', 3, 3, '## ').text).toBe('Title\nmore')
  })

  it('works on the line the cursor is in', () => {
    const edit = prefixLines('first\nsecond', 8, 8, '## ')
    expect(edit.text).toBe('first\n## second')
    expect(edit.text.slice(edit.start, edit.end)).toBe('## second')
  })
})

describe('insert', () => {
  it('replaces the selection and puts the cursor after', () => {
    expect(insert('Hi NAME,', 3, 7, '{{first_name}}')).toEqual({ text: 'Hi {{first_name}},', start: 17, end: 17 })
  })
})
