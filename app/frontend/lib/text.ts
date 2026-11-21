// Small pieces of wording shared across pages

/** "3 fields", "1 field", "1,200 people" */
export const count = (n: number, one: string, many = `${one}s`) =>
  `${n.toLocaleString('en-US')} ${n === 1 ? one : many}`
