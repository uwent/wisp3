// Display units (PLAN.md Q3). WISP stores US units (water depths in inches); this module is the only
// place values are converted, at the display and input edge. Every displayed or entered quantity
// goes through format() or parse().

export type UnitSystem = 'imperial' | 'metric'

export type Quantity =
  | 'depth' // water: rain, irrigation, ET, AD (in ↔ mm)
  | 'rootDepth' // root zone depth (in ↔ cm)
  | 'distance' // pivot radius (ft ↔ m)
  | 'area' // field area (ac ↔ ha)
  | 'flow' // pump capacity (gpm ↔ L/s)
  | 'temperature' // °F ↔ °C
  | 'degreeDays' // growing degree days (°F·d ↔ °C·d)
  | 'speed' // wind (mph ↔ km/h)

type Unit = { label: string; digits: number; toDisplay: (stored: number) => number; toStored: (shown: number) => number }

const same = (label: string, digits: number): Unit => ({ label, digits, toDisplay: (v) => v, toStored: (v) => v })
const scaled = (label: string, digits: number, factor: number): Unit => ({
  label,
  digits,
  toDisplay: (v) => v * factor,
  toStored: (v) => v / factor,
})

const UNITS: Record<Quantity, Record<UnitSystem, Unit>> = {
  depth: { imperial: same('in', 2), metric: scaled('mm', 1, 25.4) },
  rootDepth: { imperial: same('in', 0), metric: scaled('cm', 0, 2.54) },
  distance: { imperial: same('ft', 0), metric: scaled('m', 0, 0.3048) },
  area: { imperial: same('ac', 1), metric: scaled('ha', 1, 0.40468564224) },
  flow: { imperial: same('gpm', 0), metric: scaled('L/s', 1, 3.785411784 / 60) },
  temperature: {
    imperial: same('°F', 0),
    metric: { label: '°C', digits: 0, toDisplay: (f) => ((f - 32) * 5) / 9, toStored: (c) => (c * 9) / 5 + 32 },
  },
  degreeDays: { imperial: same('°F·d', 0), metric: scaled('°C·d', 0, 5 / 9) },
  speed: { imperial: same('mph', 0), metric: scaled('km/h', 0, 1.609344) },
}

export type ParseResult = { ok: true; value: number | null } | { ok: false; error: string }

export type Units = {
  system: UnitSystem
  label: (quantity: Quantity) => string
  /** The stored value in display units (unrounded), or null */
  toDisplay: (quantity: Quantity, stored: number | null | undefined) => number | null
  /** A display-unit value back to the stored unit */
  toStored: (quantity: Quantity, shown: number) => number
  /** "0.75 in", or "0.75" with unit: false; "—" for missing values */
  format: (quantity: Quantity, stored: number | null | undefined, options?: { digits?: number; unit?: boolean }) => string
  /** A display value for an input box: rounded, no unit, '' for null */
  input: (quantity: Quantity, stored: number | null | undefined, digits?: number) => string
  /** Text typed in display units → the stored value; blank is null (not entered), "0" is 0 */
  parse: (quantity: Quantity, text: string) => ParseResult
}

export const MISSING = '—'

export function units(system: UnitSystem = 'imperial'): Units {
  const unit = (quantity: Quantity) => UNITS[quantity][system]

  const toDisplay = (quantity: Quantity, stored: number | null | undefined) =>
    stored === null || stored === undefined || Number.isNaN(stored) ? null : unit(quantity).toDisplay(stored)

  return {
    system,
    label: (quantity) => unit(quantity).label,
    toDisplay,
    toStored: (quantity, shown) => unit(quantity).toStored(shown),
    format(quantity, stored, { digits, unit: withUnit = true } = {}) {
      const shown = toDisplay(quantity, stored)
      if (shown === null) return MISSING
      const text = formatNumber(shown, digits ?? unit(quantity).digits)
      return withUnit ? `${text} ${unit(quantity).label}` : text
    },
    input(quantity, stored, digits) {
      const shown = toDisplay(quantity, stored)
      return shown === null ? '' : trimZeros(shown.toFixed(digits ?? unit(quantity).digits + 1))
    },
    parse(quantity, text) {
      const parsed = parseNumber(text)
      if (!parsed.ok || parsed.value === null) return parsed
      return { ok: true, value: unit(quantity).toStored(parsed.value) }
    },
  }
}

/** A plain number (percent, fraction) typed by the user: blank is null */
export function parseNumber(text: string): ParseResult {
  const trimmed = text.trim().replace(/,/g, '')
  if (trimmed === '') return { ok: true, value: null }
  const value = Number(trimmed)
  if (!Number.isFinite(value)) return { ok: false, error: 'Enter a number' }
  return { ok: true, value }
}

export function formatNumber(value: number | null | undefined, digits = 0): string {
  if (value === null || value === undefined || Number.isNaN(value)) return MISSING
  // Avoid "-0.00"
  const rounded = Number(value.toFixed(digits))
  return (Object.is(rounded, -0) ? 0 : rounded).toLocaleString('en-US', {
    minimumFractionDigits: digits,
    maximumFractionDigits: digits,
  })
}

function trimZeros(text: string) {
  return text.includes('.') ? text.replace(/0+$/, '').replace(/\.$/, '') : text
}
