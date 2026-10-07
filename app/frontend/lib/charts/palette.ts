import { currentTheme } from '../theme'

// Chart colors from the design tokens in application.css, resolved for the current color scheme.
// ECharts can't parse oklch(), so each color is converted to rgb by painting it on a canvas.

export type Palette = {
  ink: string
  inkMuted: string
  line: string
  surface: string
  rain: string
  irrigation: string
  canopy: string
  ad: string
  warm: string
  snow: string
  depths: [string, string, string, string]
  status: { full: string; ok: string; caution: string; irrigate: string }
  dark: boolean
}

const TOKENS = {
  ink: '--color-ink',
  inkMuted: '--color-ink-muted',
  line: '--color-line',
  surface: '--color-surface-raised',
  rain: '--color-chart-rain',
  irrigation: '--color-chart-irrigation',
  canopy: '--color-chart-canopy',
  ad: '--color-chart-ad',
  warm: '--color-chart-warm',
  snow: '--color-chart-snow',
} as const

export function readPalette(element: Element = document.documentElement): Palette {
  const style = getComputedStyle(element)
  const canvas = document.createElement('canvas')
  canvas.width = canvas.height = 1
  const context = canvas.getContext('2d', { willReadFrequently: true })
  const color = (token: string) => {
    const value = style.getPropertyValue(token).trim()
    if (!context || !value) return value || '#888888'
    context.clearRect(0, 0, 1, 1)
    context.fillStyle = value
    context.fillRect(0, 0, 1, 1)
    const [r, g, b] = context.getImageData(0, 0, 1, 1).data
    return `rgb(${r}, ${g}, ${b})`
  }
  const named = Object.fromEntries(Object.entries(TOKENS).map(([key, token]) => [key, color(token)])) as Record<
    keyof typeof TOKENS,
    string
  >
  return {
    ...named,
    depths: [1, 2, 3, 4].map((i) => color(`--color-chart-depth-${i}`)) as Palette['depths'],
    status: {
      full: color('--color-status-full'),
      ok: color('--color-status-ok'),
      caution: color('--color-status-caution'),
      irrigate: color('--color-status-irrigate'),
    },
    dark: currentTheme() === 'dark',
  }
}

/** Shared axis, grid and tooltip styling */
export function baseOption(palette: Palette) {
  const axisLabel = { color: palette.inkMuted, fontSize: 11 }
  return {
    animation: false,
    textStyle: { fontFamily: getComputedStyle(document.body).fontFamily, color: palette.ink },
    tooltip: {
      trigger: 'axis' as const,
      backgroundColor: palette.surface,
      borderColor: palette.line,
      textStyle: { color: palette.ink, fontSize: 12 },
      axisPointer: { type: 'line' as const, lineStyle: { color: palette.inkMuted, width: 1 } },
      confine: true,
    },
    axisLabel,
    splitLine: { lineStyle: { color: palette.line, opacity: 0.6 } },
    axisLine: { lineStyle: { color: palette.line } },
  }
}
