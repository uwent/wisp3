<script lang="ts">
  import { Link } from '@inertiajs/svelte'

  import { newQuickSetup, setup } from '@/routes'

  // The dashboard's checklist until the operation has any planting (PLAN.md G.6): what's set up so far
  // and a link to the next step, so a step left for later in quick setup isn't lost.
  let { progress, year }: { progress: { farms: number; systems: number; fields: number }; year: number } = $props()

  const steps = $derived([
    {
      label: 'A farm',
      detail: 'Groups the irrigation systems you manage together.',
      done: progress.farms > 0,
      href: newQuickSetup(),
      action: 'Get started',
    },
    {
      label: 'An irrigation system',
      detail: 'A pivot, traveler, drip block or other system, placed on the map. WISP gets weather from its location.',
      done: progress.systems > 0,
      href: newQuickSetup(),
      action: 'Set up an irrigation system',
    },
    {
      label: 'Its fields',
      detail: 'The land each system waters, with its soil. Type them in or import their shapes.',
      done: progress.fields > 0,
      href: setup.show(),
      action: 'Add fields in Setup',
    },
    {
      label: `This season's plantings`,
      detail: `What's planted on each field in ${year}, and when it emerged. WISP tracks each planting's soil water.`,
      done: false,
      href: setup.show(),
      action: 'Add plantings in Setup',
    },
  ])
  const next = $derived(steps.findIndex((step) => !step.done))
</script>

<section class="rounded-lg border border-line bg-surface-raised p-6" aria-labelledby="getting-started">
  <h2 id="getting-started" class="text-lg font-medium">Get started with WISP</h2>
  <p class="mt-1 max-w-2xl text-sm text-ink-muted">
    A few steps, each of which can wait: WISP starts scheduling once a field has a planting.
  </p>
  <ol class="mt-4 space-y-3">
    {#each steps as step, i (step.label)}
      <li class="flex gap-3">
        <span
          class="mt-0.5 flex size-6 shrink-0 items-center justify-center rounded-full border text-xs font-medium
            {step.done ? 'border-brand-600 bg-brand-600 text-white dark:text-surface' : 'border-line text-ink-muted'}"
          aria-hidden="true">{step.done ? '✓' : i + 1}</span
        >
        <div class="min-w-0 space-y-1">
          <p class="font-medium {step.done ? 'text-ink-muted' : ''}">
            {step.label}{#if step.done}<span class="sr-only">{' (done)'}</span>{/if}
          </p>
          {#if !step.done}<p class="text-sm text-ink-muted">{step.detail}</p>{/if}
          {#if i === next}
            <Link
              href={step.href}
              class="mt-1 inline-block rounded-md bg-brand-600 px-4 py-2 text-sm font-medium text-white hover:bg-brand-700 dark:text-surface"
              >{step.action}</Link
            >
          {/if}
        </div>
      </li>
    {/each}
  </ol>
</section>
