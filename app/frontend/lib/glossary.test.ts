import { describe, expect, it } from 'vitest'

import { GLOSSARY, glossaryEntry, markTerms } from './glossary'

const marked = (text: string, seen?: Set<string>) =>
  markTerms(text, seen).map((segment) => (segment.entry ? `[${segment.text}:${segment.entry.id}]` : segment.text)).join('')

describe('markTerms', () => {
  it('marks each term once, preferring the longest wording', () => {
    expect(marked("The day's reference ET is scaled, and ET falls as reference ET does.")).toBe(
      "The day's [reference ET:reference_et] is scaled, and [ET:et] falls as reference ET does.",
    )
  })

  it('counts every wording of a term as one term', () => {
    expect(marked('Modeled from leaf area index (LAI): LAI comes from a curve.')).toBe(
      'Modeled from [leaf area index:lai] (LAI): LAI comes from a curve.',
    )
  })

  it('matches abbreviations only in capitals and only as whole words', () => {
    expect(marked('An ad for a road; AD is low.')).toBe('An ad for a road; [AD:ad] is low.')
    expect(marked('Kcal and ETA are not terms')).toBe('Kcal and ETA are not terms')
  })

  it('matches phrases in any case', () => {
    expect(marked('Field capacity, then Deep Drainage.')).toBe('[Field capacity:field_capacity], then [Deep Drainage:deep_drainage].')
  })

  it('shares what it has marked across the paragraphs of a block', () => {
    const seen = new Set<string>()
    expect(marked('Above field capacity.', seen)).toBe('Above [field capacity:field_capacity].')
    expect(marked('Back to field capacity.', seen)).toBe('Back to field capacity.')
  })

  it('leaves text without terms as one run', () => {
    expect(markTerms('Nothing to see')).toEqual([{ text: 'Nothing to see' }])
    expect(markTerms('')).toEqual([])
  })
})

describe('glossary', () => {
  it('has unique ids and wordings', () => {
    expect(new Set(GLOSSARY.map((entry) => entry.id)).size).toBe(GLOSSARY.length)
    const wordings = GLOSSARY.flatMap((entry) => entry.matches.map((match) => match.toLowerCase()))
    expect(new Set(wordings).size).toBe(wordings.length)
  })

  it('looks entries up by id, and fails loudly on a typo', () => {
    expect(glossaryEntry('lai').term).toBe('Leaf area index (LAI)')
    expect(() => glossaryEntry('lia')).toThrow('No glossary entry "lia"')
  })
})
