<script lang="ts">
  import { Form, page, router } from '@inertiajs/svelte'
  import { onDestroy, untrack } from 'svelte'
  import { SvelteSet } from 'svelte/reactivity'

  import Button from '@/lib/components/Button.svelte'
  import EmailPreview, { type DigestPreview } from '@/lib/components/EmailPreview.svelte'
  import SelectField from '@/lib/components/SelectField.svelte'
  import { LEAD_DAYS } from '@/lib/outlook'
  import { alerts } from '@/routes'

  type Frequency = 'never' | 'daily' | 'daily_all_year' | 'needed'
  type Scope = 'all' | 'in_season' | 'needs_action' | 'needs_irrigation'
  type DigestField = { id: number; name: string }
  type DigestPivot = { id: number; name: string; fields: DigestField[] }
  type DigestFarm = { id: number; name: string; pivots: DigestPivot[] }
  type DigestGroup = { id: number; name: string; farms: DigestFarm[] }

  let {
    frequency,
    scope,
    field_ids,
    groups,
    test_wait,
    preview,
  }: {
    frequency: Frequency
    scope: Scope
    field_ids: number[]
    groups: DigestGroup[]
    test_wait: number
    // Loaded only when asked for (an optional prop)
    preview?: DigestPreview
  } = $props()

  const frequencies: { value: Frequency; label: string; hint: string }[] = [
    { value: 'never', label: 'Never', hint: 'WISP won’t email you about your fields.' },
    {
      value: 'daily',
      label: 'Daily during season',
      hint: 'Every morning while a field has a crop in season, whether or not anything needs doing.',
    },
    {
      value: 'daily_all_year',
      label: 'Daily all year',
      hint: 'Every morning, all year: weather for your pivots even when nothing is in season.',
    },
    {
      value: 'needed',
      label: 'Only when irrigation is needed',
      hint: `Only on mornings when a field needs irrigation now or within ${LEAD_DAYS} days (Irrigate or Caution).`,
    },
  ]

  const scopes: { value: Scope; label: string; hint: string }[] = [
    {
      value: 'all',
      label: 'All the fields it covers',
      hint: 'Every field below, in season or not, with its pivot’s weather.',
    },
    {
      value: 'in_season',
      label: 'Fields with a crop in season',
      hint: 'Every field below that has a crop in season today.',
    },
    {
      value: 'needs_action',
      label: 'Fields needing irrigation or readings',
      hint: `Fields to irrigate now or within ${LEAD_DAYS} days, or with a soil moisture or canopy reading due.`,
    },
    {
      value: 'needs_irrigation',
      label: 'Only fields needing irrigation',
      hint: `Fields to irrigate now or within ${LEAD_DAYS} days (Irrigate or Caution).`,
    },
  ]

  // The settings as shown, from the props when the page opens; after that the page is the source of
  // truth and each change saves itself (the props aren't reloaded, so a save can't undo a later click)
  let chosen = $state<Frequency>(untrack(() => frequency))
  let chosenScope = $state<Scope>(untrack(() => scope))
  const picked = new SvelteSet<number>(untrack(() => field_ids))
  const farmFields = (farm: DigestFarm) => farm.pivots.flatMap((pivot) => pivot.fields)
  const groupFields = (group: DigestGroup) => group.farms.flatMap(farmFields)
  const allFields = $derived(groups.flatMap(groupFields))
  // Operations get their own checkbox only when there's more than one with fields
  const severalGroups = $derived(groups.filter((group) => groupFields(group).length).length > 1)
  const pickedCount = (fields: DigestField[]) => fields.filter((field) => picked.has(field.id)).length
  function pickAll(fields: DigestField[], on: boolean) {
    for (const field of fields) {
      if (on) picked.add(field.id)
      else picked.delete(field.id)
    }
  }
  /** A parent checkbox: checked when all its fields are, mixed when some are */
  const mixed = (fields: DigestField[]) => (node: HTMLInputElement) => {
    const count = pickedCount(fields)
    node.indeterminate = count > 0 && count < fields.length
  }

  // The preview stays open once asked for, and reloads after each save
  let previewOpen = $state(false)
  let previewLoading = $state(false)
  function loadPreview() {
    previewOpen = true
    previewLoading = true
    router.reload({ only: ['preview'], onFinish: () => (previewLoading = false) })
  }

  // Saving: a change waits SAVE_DELAY ms for more (clicking through checkboxes), then the whole
  // selection is sent. The preview and test email wait until it's saved.
  const SAVE_DELAY = 400
  let saveState = $state<'saved' | 'pending' | 'saving' | 'failed'>('saved')
  let saveError = $state<string | null>(null)
  let timer: ReturnType<typeof setTimeout> | undefined
  function save() {
    timer = undefined
    router.patch(
      alerts.update().url,
      { digest: { frequency: chosen, scope: chosenScope, field_ids: ['', ...picked] } },
      {
        preserveScroll: true,
        preserveState: true,
        only: previewOpen ? ['errors', 'preview'] : ['errors'],
        onStart: () => (saveState = 'saving'),
        onSuccess: () => {
          // A change made while this was on its way is saved by its own timer
          if (!timer) saveState = 'saved'
          saveError = null
        },
        onError: (errors) => {
          saveState = 'failed'
          saveError = [Object.values(errors)[0]].flat()[0] ?? 'Couldn’t save the settings.'
        },
      },
    )
  }
  let loaded = false
  $effect(() => {
    // Every setting the save sends
    void [chosen, chosenScope, ...picked]
    if (!loaded) {
      loaded = true
      return
    }
    saveState = 'pending'
    clearTimeout(timer)
    timer = setTimeout(save, SAVE_DELAY)
  })
  onDestroy(() => {
    if (timer) {
      clearTimeout(timer)
      save()
    }
  })
  const saved = $derived(saveState === 'saved')
  const testOptions = { preserveScroll: true, preserveState: true, only: ['test_wait'] }

  // Counts down to when another test email may be sent (the server enforces the same wait)
  let now = $state(Date.now())
  const testAt = $derived(untrack(() => now) + test_wait * 1000)
  const testRemaining = $derived(Math.max(0, Math.ceil((testAt - now) / 1000)))
  $effect(() => {
    const timer = setInterval(() => (now = Date.now()), 1000)
    return () => clearInterval(timer)
  })
  const waitLabel = (seconds: number) => (seconds > 60 ? `${Math.ceil(seconds / 60)} min` : `${seconds} s`)
</script>

<svelte:head><title>Alerts · WISP</title></svelte:head>

<div>
  <h1 class="text-2xl font-semibold">Alerts</h1>
  <p class="text-sm text-ink-muted">
    A morning email at about 6 am with your fields by operation, farm, weather zone (pivots sharing the same weather)
    and pivot, each zone's weather for the past and coming week, which fields to irrigate or watch, with when and how
    much, and the readings due on each field.
  </p>
</div>

<section class="space-y-4 rounded-lg border border-line bg-surface-raised p-6">
  <div class="flex flex-wrap items-baseline justify-between gap-2">
    <h2 class="text-lg font-medium">Daily email</h2>
    <p class="text-sm {saveState === 'failed' ? 'text-status-irrigate' : 'text-ink-muted'}" role="status">
      {#if saveState === 'failed'}{saveError}{:else if saved}Changes save automatically{:else}Saving…{/if}
    </p>
  </div>
  <div class="max-w-xl space-y-4">
    <SelectField
      label="Email frequency"
      name="digest[frequency]"
      options={frequencies}
      bind:value={chosen}
      hint={frequencies.find((option) => option.value === chosen)?.hint}
    />
    <SelectField
      label="Fields in the email"
      name="digest[scope]"
      options={scopes}
      bind:value={chosenScope}
      hint={scopes.find((option) => option.value === chosenScope)?.hint}
    />
    {#if allFields.length}
      <fieldset class="space-y-3 {chosen === 'never' ? 'opacity-60' : ''}">
        <legend class="text-sm font-medium">Fields it covers</legend>
        <p class="text-sm text-ink-muted">
          New fields are included, unless their pivot, farm or operation is left out entirely.
          {pickedCount(allFields)} of {allFields.length} included.
        </p>
        {#each groups as group (group.id)}
          {@const fields = groupFields(group)}
          {#if fields.length}
            <div class="space-y-2">
              {#if severalGroups}
                <label class="flex items-center gap-2 text-sm font-medium">
                  <input
                    type="checkbox"
                    checked={pickedCount(fields) === fields.length}
                    {@attach mixed(fields)}
                    onchange={(event) => pickAll(fields, event.currentTarget.checked)}
                  />
                  <span><span class="font-normal text-ink-muted">Operation:</span> {group.name}</span>
                </label>
              {/if}
              {#each group.farms as farm (farm.id)}
                {@const fields = farmFields(farm)}
                {#if fields.length}
                  <div class="space-y-1 {severalGroups ? 'pl-6' : ''}">
                    <label class="flex items-center gap-2 text-sm font-medium">
                      <input
                        type="checkbox"
                        checked={pickedCount(fields) === fields.length}
                        {@attach mixed(fields)}
                        onchange={(event) => pickAll(fields, event.currentTarget.checked)}
                      />
                      <span><span class="font-normal text-ink-muted">Farm:</span> {farm.name}</span>
                    </label>
                    {#each farm.pivots as pivot (pivot.id)}
                      {#if pivot.fields.length}
                        <div class="space-y-1 pl-6">
                          <label class="flex items-center gap-2 text-sm">
                            <input
                              type="checkbox"
                              checked={pickedCount(pivot.fields) === pivot.fields.length}
                              {@attach mixed(pivot.fields)}
                              onchange={(event) => pickAll(pivot.fields, event.currentTarget.checked)}
                            />
                            <span><span class="text-ink-muted">Pivot:</span> {pivot.name}</span>
                          </label>
                          <div class="grid gap-1 pl-6 sm:grid-cols-2">
                            {#each pivot.fields as field (field.id)}
                              <label class="flex items-center gap-2 text-sm">
                                <input
                                  type="checkbox"
                                  name="digest[field_ids][]"
                                  value={field.id}
                                  checked={picked.has(field.id)}
                                  onchange={(event) => pickAll([field], event.currentTarget.checked)}
                                />
                                {field.name}
                              </label>
                            {/each}
                          </div>
                        </div>
                      {/if}
                    {/each}
                  </div>
                {/if}
              {/each}
            </div>
          {/if}
        {/each}
      </fieldset>
    {:else}
      <p class="text-sm text-ink-muted">Once you've added fields, every one of them is included.</p>
    {/if}
  </div>
</section>

<section class="space-y-4 rounded-lg border border-line bg-surface-raised p-6">
  <div>
    <h2 class="text-lg font-medium">Today's email</h2>
    <p class="text-sm text-ink-muted">
      See the email your saved settings give with today's data, or send it to {page.props.auth.user?.email} now, whatever
      the frequency.
    </p>
  </div>
  <div class="flex flex-wrap gap-2">
    <Button variant="secondary" onclick={loadPreview} disabled={previewLoading || !saved}>
      {previewOpen && preview ? 'Refresh preview' : 'Preview today’s email'}
    </Button>
    <Form action={alerts.testEmail()} options={testOptions}>
      {#snippet children({ processing })}
        <Button type="submit" variant="secondary" disabled={processing || testRemaining > 0 || !saved}>
          {testRemaining > 0 ? `Send a test email (again in ${waitLabel(testRemaining)})` : 'Send me a test email'}
        </Button>
      {/snippet}
    </Form>
  </div>
  {#if previewOpen}
    {#if preview}
      <EmailPreview {preview} />
    {:else}
      <p class="text-sm text-ink-muted">Loading the preview…</p>
    {/if}
  {/if}
</section>
