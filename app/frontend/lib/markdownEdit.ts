// The announcement composer's toolbar (pages/Admin/Announcements/Form.svelte): Markdown syntax put
// around the selection or at the start of its lines. Each takes the text and the selection and
// returns the new text with what to select next, so the textarea keeps its place.

export type Edit = { text: string; start: number; end: number }

/** Wraps the selection (or, without one, `empty`, selected for typing over) in `before` and `after` */
export function wrap(text: string, start: number, end: number, before: string, after: string, empty: string): Edit {
  const inner = text.slice(start, end) || empty
  return {
    text: text.slice(0, start) + before + inner + after + text.slice(end),
    start: start + before.length,
    end: start + before.length + inner.length,
  }
}

/** A link around the selection, its address selected for typing */
export function link(text: string, start: number, end: number): Edit {
  const label = text.slice(start, end) || 'link text'
  const url = 'https://'
  const inserted = `[${label}](${url})`
  const urlStart = start + label.length + 3
  return { text: text.slice(0, start) + inserted + text.slice(end), start: urlStart, end: urlStart + url.length }
}

/**
 * Starts each line the selection touches with `prefix` ("## ", "- "), or "1. ", "2. " … when
 * `numbered`; a line already starting so has it taken off instead
 */
export function prefixLines(text: string, start: number, end: number, prefix: string, numbered = false): Edit {
  const lineStart = text.lastIndexOf('\n', start - 1) + 1
  const nextBreak = text.indexOf('\n', Math.max(end - (end > start && text[end - 1] === '\n' ? 1 : 0), start))
  const lineEnd = nextBreak === -1 ? text.length : nextBreak
  const lines = text.slice(lineStart, lineEnd).split('\n')
  const marker = (i: number) => (numbered ? `${i + 1}. ` : prefix)
  const pattern = numbered ? /^\d+\. / : new RegExp(`^${prefix.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}`)
  const removing = lines.every((line) => pattern.test(line))
  const changed = lines.map((line, i) => (removing ? line.replace(pattern, '') : marker(i) + line)).join('\n')
  return {
    text: text.slice(0, lineStart) + changed + text.slice(lineEnd),
    start: lineStart,
    end: lineStart + changed.length,
  }
}

/** `insertion` in place of the selection, the cursor after it */
export function insert(text: string, start: number, end: number, insertion: string): Edit {
  const at = start + insertion.length
  return { text: text.slice(0, start) + insertion + text.slice(end), start: at, end: at }
}
