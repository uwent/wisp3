<script lang="ts">
  import { onMount } from 'svelte'

  import { echarts, type ChartView, type EChartsCoreOption } from './echarts'
  import { onThemeChange } from '../theme'
  import { readPalette, type Palette } from './palette'

  // build turns the current palette into the chart's option; it's rebuilt when the data it reads
  // changes or the theme switches. It also gets the days in view once the user zooms, for values
  // that depend on them (running totals). modified is true once the user zooms or toggles a series;
  // reset() puts the chart back as it opened.
  let {
    build,
    height = '18rem',
    label,
    modified = $bindable(false),
  }: {
    build: (palette: Palette, view?: ChartView) => EChartsCoreOption
    height?: string
    label: string
    modified?: boolean
  } = $props()

  let element: HTMLDivElement
  let chart: echarts.ECharts | undefined = $state()
  let palette: Palette | undefined = $state()
  // The user's zoom (percent of the x range) and legend choices, kept when the data reloads after an edit
  let zoom: { start: number; end: number } | undefined
  let view: ChartView | undefined
  let legend: Record<string, boolean> | undefined

  function withState(option: EChartsCoreOption): EChartsCoreOption {
    let result = option
    if (zoom && Array.isArray(option.dataZoom)) {
      const { start, end } = zoom
      result = { ...result, dataZoom: option.dataZoom.map((dz: object) => ({ ...dz, start, end, startValue: undefined, endValue: undefined })) }
    }
    if (legend && option.legend) result = { ...result, legend: { ...(option.legend as object), selected: legend } }
    return result
  }

  export function reset() {
    zoom = view = legend = undefined
    modified = false
    if (chart && palette) chart.setOption(build(palette), { notMerge: true })
  }

  onMount(() => {
    chart = echarts.init(element, null, { renderer: 'canvas' })
    palette = readPalette()
    chart.on('datazoom', () => {
      const option = chart?.getOption()
      const [dz] = (option?.dataZoom as { start: number; end: number }[] | undefined) ?? []
      if (!dz || !palette) return
      zoom = { start: dz.start, end: dz.end }
      const count = ((option?.xAxis as { data?: unknown[] }[] | undefined)?.[0]?.data?.length ?? 1) - 1
      view = { start: Math.round((dz.start / 100) * count), end: Math.round((dz.end / 100) * count) }
      modified = true
      chart?.setOption(withState(build(palette, view)), { lazyUpdate: true })
    })
    chart.on('legendselectchanged', (event) => {
      legend = (event as { selected: Record<string, boolean> }).selected
      modified = true
    })
    const offTheme = onThemeChange(() => (palette = readPalette()))
    // Canvas text uses whatever font is loaded when it's drawn; redraw once the web fonts are in
    document.fonts?.ready.then(() => chart && (palette = readPalette()))
    const observer = new ResizeObserver(() => chart?.resize())
    observer.observe(element)
    return () => {
      offTheme()
      observer.disconnect()
      chart?.dispose()
    }
  })

  $effect(() => {
    if (chart && palette) chart.setOption(withState(build(palette, view)), { notMerge: true, lazyUpdate: true })
  })
</script>

<div bind:this={element} style:height role="img" aria-label={label} class="w-full"></div>
