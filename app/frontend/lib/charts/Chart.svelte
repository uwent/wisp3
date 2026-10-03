<script lang="ts">
  import { onMount } from 'svelte'

  import { echarts, type EChartsCoreOption } from './echarts'
  import { onThemeChange } from '../theme'
  import { readPalette, type Palette } from './palette'

  // build turns the current palette into the chart's option; it's rebuilt when the data it reads
  // changes or the theme switches
  let {
    build,
    height = '18rem',
    label,
  }: { build: (palette: Palette) => EChartsCoreOption; height?: string; label: string } = $props()

  let element: HTMLDivElement
  let chart: echarts.ECharts | undefined = $state()
  let palette: Palette | undefined = $state()
  // The user's zoom (percent of the x range), kept when the data reloads after an edit
  let zoom: { start: number; end: number } | undefined

  function withZoom(option: EChartsCoreOption): EChartsCoreOption {
    if (!zoom || !Array.isArray(option.dataZoom)) return option
    const { start, end } = zoom
    return {
      ...option,
      dataZoom: option.dataZoom.map((dz: object) => ({ ...dz, start, end, startValue: undefined, endValue: undefined })),
    }
  }

  onMount(() => {
    chart = echarts.init(element, null, { renderer: 'canvas' })
    palette = readPalette()
    chart.on('datazoom', () => {
      const [dz] = (chart?.getOption().dataZoom as { start: number; end: number }[] | undefined) ?? []
      if (dz) zoom = { start: dz.start, end: dz.end }
    })
    const offTheme = onThemeChange(() => (palette = readPalette()))
    const observer = new ResizeObserver(() => chart?.resize())
    observer.observe(element)
    return () => {
      offTheme()
      observer.disconnect()
      chart?.dispose()
    }
  })

  $effect(() => {
    if (chart && palette) chart.setOption(withZoom(build(palette)), { notMerge: true, lazyUpdate: true })
  })
</script>

<div bind:this={element} style:height role="img" aria-label={label} class="w-full"></div>
