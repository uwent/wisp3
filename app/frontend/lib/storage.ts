// Settings remembered in this browser (a collapsed row, a chosen order). Storage can be blocked
// (a private window, a browser setting) or hold anything, so reading and writing never throw: a
// setting that can't be read is undefined, and one that can't be saved lasts for this page only.

/** What's saved under key (JSON), or undefined if nothing is or storage is blocked. Text saved
 * before settings were JSON ("name", "off") comes back as that string. */
export function readStored(key: string): unknown {
  let text: string | null
  try {
    text = localStorage.getItem(key)
  } catch {
    return undefined
  }
  if (text === null) return undefined
  try {
    return JSON.parse(text)
  } catch {
    return text
  }
}

/** Saves value under key as JSON; false if storage is blocked */
export function writeStored(key: string, value: unknown): boolean {
  try {
    localStorage.setItem(key, JSON.stringify(value))
    return true
  } catch {
    return false
  }
}
