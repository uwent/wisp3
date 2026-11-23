import type { Choice } from './matching'
import type { ImportedShape } from './read'

/**
 * One usable shape on Setup's import, and where it goes. A class, so its shape stays a plain object:
 * deep $state would proxy every coordinate, and the geometry run over them (overlaps, distances)
 * becomes many times slower. Only what the grower changes is reactive.
 */
export class ImportRow {
  readonly shape: ImportedShape
  systemId = $state<number | null>(null)
  choice = $state.raw<Choice>({ kind: 'skip' })
  /** A new field's name: the shape's, until the grower types one */
  name = $state('')
  nameEdited = $state(false)
  soilTypeId = $state(0)
  soil = $state<'default' | 'survey' | 'chosen'>('default')
  /** Has a card: matched or new to start with, or added from the skipped shapes (always Skip otherwise) */
  carded = $state(false)
  /** The field last chosen to update, offered again when Update is chosen again */
  lastFieldId = $state<number | null>(null)

  constructor(
    shape: ImportedShape,
    init: { systemId: number | null; choice: Choice; name: string; soilTypeId: number },
  ) {
    this.shape = shape
    this.systemId = init.systemId
    this.choice = init.choice
    this.name = init.name
    this.soilTypeId = init.soilTypeId
    this.carded = init.choice.kind !== 'skip'
    this.lastFieldId = init.choice.kind === 'field' ? init.choice.fieldId : null
  }
}
