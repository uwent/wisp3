<script lang="ts">
  import { Link } from '@inertiajs/svelte'

  import Introduction from '@/lib/docs/Introduction.svelte'
  import { about, newUserRegistration, newUserSession } from '@/routes'

  // The landing page for signed-out visitors (PLAN.md Phase 6.5); signed in, / is the dashboard

  const steps = [
    {
      title: 'Set up your fields',
      text: 'Place each pivot on the map and add its fields with their crop, emergence date and soil.',
      anchor: 'getting-started',
    },
    {
      title: 'Weather comes in',
      text: 'Each pivot gets its own rain and reference ET three times a day, with a 16-day forecast.',
      anchor: 'how-it-works',
    },
    {
      title: 'Enter what you measure',
      text: 'Rain gauges, irrigation and soil moisture readings keep each field’s balance true.',
      anchor: 'ground-truthing',
    },
    {
      title: 'Know when to irrigate',
      text: 'The dashboard and a morning email show which fields need water, by when, and how much.',
      anchor: 'day-to-day',
    },
  ]
</script>

<svelte:head><title>WISP · Wisconsin Irrigation Scheduling Program</title></svelte:head>

<section class="grid gap-8 py-4 lg:grid-cols-[3fr_2fr] lg:items-center lg:py-10">
  <div class="space-y-5">
    <h1 class="font-display text-3xl font-semibold tracking-tight sm:text-4xl">
      Irrigate when your fields need it, not before
    </h1>
    <div class="prose max-w-2xl">
      <Introduction />
    </div>
    <div class="flex flex-wrap gap-3">
      <Link
        href={newUserRegistration()}
        class="rounded-md bg-brand-600 px-4 py-2 text-sm font-medium text-white hover:bg-brand-700 dark:text-surface"
      >
        Create a free account
      </Link>
      <Link
        href={newUserSession()}
        class="rounded-md border border-line bg-surface-raised px-4 py-2 text-sm font-medium hover:bg-surface"
      >
        Sign in
      </Link>
      <Link href={about()} class="px-2 py-2 text-sm font-medium text-brand-600 hover:underline">How WISP works →</Link>
    </div>
  </div>

  <ol class="grid gap-3 sm:grid-cols-2 lg:grid-cols-1">
    {#each steps as step, i (step.title)}
      <li class="rounded-lg border border-line bg-surface-raised p-4">
        <Link href={about({ anchor: step.anchor })} class="group block">
          <p class="text-xs font-medium text-brand-600">Step {i + 1}</p>
          <h2 class="font-medium group-hover:underline">{step.title}</h2>
          <p class="mt-1 text-sm text-ink-muted">{step.text}</p>
        </Link>
      </li>
    {/each}
  </ol>
</section>
