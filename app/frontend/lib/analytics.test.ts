import { describe, expect, it } from 'vitest'

import { cleanUrl, tracked } from './analytics'

describe('cleanUrl', () => {
  it('keeps the address and utm_ parameters, and drops every other parameter and the fragment', () => {
    expect(cleanUrl('https://wisp.example/?utm_source=email&utm_campaign=launch&ref=x#top')).toBe(
      'https://wisp.example/?utm_source=email&utm_campaign=launch',
    )
    expect(cleanUrl('https://wisp.example/account/sign_in?email=pat%40farm.test')).toBe(
      'https://wisp.example/account/sign_in',
    )
  })

  it("drops the tokens in emailed links' addresses", () => {
    expect(cleanUrl('https://wisp.example/account/sign_in_link/open?token=secret')).toBe(
      'https://wisp.example/account/sign_in_link/open',
    )
    expect(cleanUrl('/account/password/edit?reset_password_token=secret', 'https://wisp.example')).toBe(
      'https://wisp.example/account/password/edit',
    )
  })

  it("is empty for what isn't an address", () => {
    expect(cleanUrl('not a url')).toBe('')
  })
})

describe('tracked', () => {
  const page = (component: string, props: { auth?: { user?: unknown }; example?: unknown } = {}) => ({
    component,
    props: { auth: { user: null }, ...props },
  })

  it('tracks the listed public pages, signed out', () => {
    expect(tracked(page('Pages/Home'))).toBe(true)
    expect(tracked(page('Auth/SignUp'))).toBe(true)
  })

  it('leaves out pages reached with a token, and everything signed in', () => {
    expect(tracked(page('Auth/MagicLink'))).toBe(false)
    expect(tracked(page('Auth/ResetPassword'))).toBe(false)
    expect(tracked(page('Auth/Unsubscribe'))).toBe(false)
    expect(tracked(page('Pages/About', { auth: { user: { id: 1 } } }))).toBe(false)
    expect(tracked(page('Dashboard/Show'))).toBe(false)
  })

  it("tracks the example farm's pages, unless signed in", () => {
    expect(tracked(page('Fields/Show', { example: { as_of: '2026-07-20' } }))).toBe(true)
    expect(tracked(page('Fields/Show', { example: { as_of: '2026-07-20' }, auth: { user: { id: 1 } } }))).toBe(false)
  })
})
