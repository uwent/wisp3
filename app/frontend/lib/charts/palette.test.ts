import { describe, expect, it } from 'vitest'

import { hex } from './palette'

describe('hex', () => {
  it("writes readPalette's rgb as #rrggbb for terra-draw, and leaves hex as it is", () => {
    expect(hex('rgb(46, 196, 240)')).toBe('#2ec4f0')
    expect(hex('rgb(0, 0, 0)')).toBe('#000000')
    expect(hex('#888888')).toBe('#888888')
  })
})
