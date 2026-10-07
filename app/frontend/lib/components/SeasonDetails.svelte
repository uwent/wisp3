<script lang="ts">
  import { DISAGREE_IN, RAIN_DAY, type SeasonStats } from '../seasonStats'
  import type { Units } from '../units'
  import Term from './Term.svelte'

  // The season in numbers on a field's page: rain entered and modeled, the gauge against the
  // model day by day, irrigation and deep drainage ("stats for nerds")
  let { stats, units, useModelPrecip }: { stats: SeasonStats; units: Units; useModelPrecip: boolean } = $props()

  const depth = (inches: number) => units.format('depth', inches)
  const days = (count: number) => `${count} ${count === 1 ? 'day' : 'days'}`
  const daysOf = (total: { days: number; inches: number }) =>
    total.days ? `${days(total.days)}, ${depth(total.inches)}` : 'None'
  const signed = (inches: number) => `${inches > 0 ? '+' : ''}${depth(inches)}`
  const { comparison } = $derived(stats)
</script>

<div class="grid gap-x-8 gap-y-5 text-sm md:grid-cols-3">
  <div>
    <h3 class="font-medium">Rain</h3>
    <dl class="mt-1 space-y-1.5">
      <div>
        <dt class="text-ink-muted">Entered</dt>
        <dd class="tabular-nums">
          {#if stats.entered.readings}
            {depth(stats.entered.inches)} · {stats.entered.readings}
            {stats.entered.readings === 1 ? 'reading' : 'readings'}, {stats.entered.rainDays} with rain
          {:else}None{/if}
        </dd>
      </div>
      <div>
        <dt class="text-ink-muted">Modeled</dt>
        <dd class="tabular-nums">{depth(stats.modeled.inches)} on {days(stats.modeled.days)} with rain</dd>
      </div>
      {#if !useModelPrecip}
        <div>
          <dt class="text-ink-muted">Modeled, left out of the balance</dt>
          <dd class="tabular-nums">{daysOf(stats.leftOut)}</dd>
        </div>
      {/if}
    </dl>
  </div>

  <div>
    <h3 class="font-medium">Your gauge and the model</h3>
    {#if stats.entered.readings}
      <dl class="mt-1 space-y-1.5">
        <div>
          <dt class="text-ink-muted">Both had rain</dt>
          <dd class="tabular-nums">
            {#if comparison.both.days}
              {days(comparison.both.days)}; they disagreed on {comparison.both.disagree}
            {:else}None{/if}
          </dd>
        </div>
        {#if comparison.both.typicalAdjustment !== null}
          <div>
            <dt class="text-ink-muted">Typical correction (gauge − model)</dt>
            <dd class="tabular-nums">
              {signed(comparison.both.typicalAdjustment)}{#if comparison.both.ratio !== null}; your gauge read {Math.round(
                  comparison.both.ratio * 100,
                )}% of the model{/if}
            </dd>
          </div>
        {/if}
        <div>
          <dt class="text-ink-muted">You had rain, the model none</dt>
          <dd class="tabular-nums">{daysOf(comparison.missed)}</dd>
        </div>
        <div>
          <dt class="text-ink-muted">You entered 0, the model had rain</dt>
          <dd class="tabular-nums">{daysOf(comparison.zeroed)}</dd>
        </div>
        <div>
          <dt class="text-ink-muted">Model rain, no reading</dt>
          <dd class="tabular-nums">{daysOf(comparison.noReading)}</dd>
        </div>
      </dl>
    {:else}
      <p class="mt-1 text-ink-muted">
        Enter your rain gauge readings to see how they compare with the model, day by day.
      </p>
    {/if}
  </div>

  <div>
    <h3 class="font-medium">Irrigation and drainage</h3>
    <dl class="mt-1 space-y-1.5">
      <div>
        <dt class="text-ink-muted">Irrigation</dt>
        <dd class="tabular-nums">
          {stats.irrigation.days ? `${depth(stats.irrigation.inches)} on ${days(stats.irrigation.days)}` : 'None'}
        </dd>
      </div>
      {#if stats.irrigation.typicalAmount !== null}
        <div>
          <dt class="text-ink-muted">Typical irrigation</dt>
          <dd class="tabular-nums">
            {depth(stats.irrigation.typicalAmount)}{#if stats.irrigation.typicalInterval !== null}, every {days(
                stats.irrigation.typicalInterval,
              )}{/if}
          </dd>
        </div>
      {/if}
      <div>
        <dt class="text-ink-muted"><Term id="deep_drainage">Deep drainage</Term></dt>
        <dd class="tabular-nums">{depth(stats.deepDrainage)}</dd>
      </div>
    </dl>
  </div>
</div>
<p class="text-xs text-ink-muted">
  The season through today ({days(stats.days)}). A rain day has at least {units.format('depth', RAIN_DAY)}. Gauge and
  model disagree when they differ by more than {units.format('depth', DISAGREE_IN)} or a quarter of the model's amount; typical
  values are medians. "No reading" may mean no rain, or a gauge nobody read.
</p>
