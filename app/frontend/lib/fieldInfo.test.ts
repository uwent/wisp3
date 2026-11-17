import { readdirSync, readFileSync } from 'node:fs'
import { join } from 'node:path'
import { describe, expect, it } from 'vitest'

import { FIELD_INFO, fieldInfo, type FieldInfoKey } from './fieldInfo'
import { units } from './units'

const keys = Object.keys(FIELD_INFO) as FieldInfoKey[]

// Every .svelte and .ts file under app/frontend except this module and its test
const root = join(__dirname, '..')
const sources = (readdirSync(root, { recursive: true }) as string[])
  .filter((path) => /\.(svelte|ts)$/.test(path) && !/fieldInfo(\.test)?\.ts$/.test(path))
  .map((path) => readFileSync(join(root, path), 'utf8'))
  .join('\n')

describe('fieldInfo', () => {
  it.each(keys)('%s is at most two sentences, in either unit system', (key) => {
    for (const system of ['imperial', 'metric'] as const) {
      const { text } = fieldInfo(key, units(system))
      const sentences = text.split(/[.!?](?:\s|$)/).filter((part) => part.trim())
      expect(sentences.length).toBeLessThanOrEqual(2)
      expect(text).toMatch(/[.!?]$/)
    }
  })

  it.each(keys)('%s is used in a form', (key) => {
    expect(sources).toMatch(new RegExp(`['"]${key.replace('.', '\\.')}['"]`))
  })

  it('names glossary terms that exist', () => {
    for (const key of keys) expect(() => fieldInfo(key, units('imperial'))).not.toThrow()
  })
})
