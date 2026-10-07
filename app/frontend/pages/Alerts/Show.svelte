<script lang="ts">
  import { Form, page, router } from '@inertiajs/svelte'
  import { untrack } from 'svelte'
  import { SvelteSet } from 'svelte/reactivity'

  import Button from '@/lib/components/Button.svelte'
  import EmailPreview, { type DigestPreview } from '@/lib/components/EmailPreview.svelte'
  import SelectField from '@/lib/components/SelectField.svelte'
  import { LEAD_DAYS } from '@/lib/outlook'
  import { alerts } from '@/routes'

  type Frequency = 'never' | 'daily' | 'needed'
  type DigestField = { id: number; name: string; pivot: string }
  type DigestFarm = { id: number; name: string; fields: DigestField[] }
  type DigestGroup = { id: number; name: string; farms: DigestFarm[] }

  let {
    frequency,
    field_ids,
    groups,
    test_wait,
    preview,
  }: {
    frequency: Frequency
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
      value: 'needed',
      label: 'Only when irrigation is needed',
      hint: `Only on mornings when a field needs irrigation now or within ${LEAD_DAYS} days (Irrigate or Caution).`,
    },
  ]

  // The form's state, reset from the props after each save
  let chosen = $state<Frequency>('daily')
  const picked = new SvelteSet<number>()
  $effect.pre(() => {
    chosen = frequency
    picked.clear()
    for (const id of field_ids) picked.add(id)
  })
  const groupFields = (group: DigestGroup) => group.farms.flatMap((farm) => farm.fields)
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

  // The preview stays open once asked for, and reloads after the settings are saved
  let previewOpen = $state(false)
  let previewLoading = $state(false)
  function loadPreview() {
    previewOpen = true
    previewLoading = true
    router.reload({ only: ['preview'], onFinish: () => (previewLoading = false) })
  }
  // Both forms keep the page's state and reload only the props they change, in the same request as
  // the save, so the flash message stays. Saving settings rebuilds an open preview; a test send
  // leaves it as it is.
  const settingsProps = ['frequency', 'field_ids', 'groups', 'test_wait']
  const saveOptions = $derived({
    preserveScroll: true,
    preserveState: true,
    only: previewOpen ? [...settingsProps, 'preview'] : settingsProps,
  })
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
    A morning email at about 6 am with your fields by farm and pivot, each pivot's weather for the past and coming week,
    and which fields to irrigate or watch, with when and how much.
  </p>
</div>

<section class="space-y-4 rounded-lg border border-line bg-surface-raised p-6">
  <h2 class="text-lg font-medium">Daily email</h2>
  <Form action={alerts.update()} class="max-w-xl space-y-4" options={saveOptions}>
    {#snippet children({ errors, processing })}
      <SelectField
        label="Email frequency"
        name="digest[frequency]"
        options={frequencies}
        bind:value={chosen}
        hint={frequencies.find((option) => option.value === chosen)?.hint}
        error={errors.digest_frequency}
      />
      <input type="hidden" name="digest[field_ids][]" value="" />
      {#if allFields.length}
        <fieldset class="space-y-3 {chosen === 'never' ? 'opacity-60' : ''}">
          <legend class="text-sm font-medium">Fields it covers</legend>
          <p class="text-sm text-ink-muted">
            New fields are included, unless their farm or operation is left out entirely.
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
                    {group.name}
                  </label>
                {/if}
                {#each group.farms as farm (farm.id)}
                  {#if farm.fields.length}
                    <div class="space-y-1 {severalGroups ? 'pl-6' : ''}">
                      <label class="flex items-center gap-2 text-sm font-medium">
                        <input
                          type="checkbox"
                          checked={pickedCount(farm.fields) === farm.fields.length}
                          {@attach mixed(farm.fields)}
                          onchange={(event) => pickAll(farm.fields, event.currentTarget.checked)}
                        />
                        {farm.name}
                      </label>
                      <div class="grid gap-1 pl-6 sm:grid-cols-2">
                        {#each farm.fields as field (field.id)}
                          <label class="flex items-center gap-2 text-sm">
                            <input
                              type="checkbox"
                              name="digest[field_ids][]"
                              value={field.id}
                              checked={picked.has(field.id)}
                              onchange={(event) => pickAll([field], event.currentTarget.checked)}
                            />
                            <span>{field.name} <span class="text-ink-muted">· {field.pivot}</span></span>
                          </label>
                        {/each}
                      </div>
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
      <Button type="submit" disabled={processing}>Save alert settings</Button>
    {/snippet}
  </Form>
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
    <Button variant="secondary" onclick={loadPreview} disabled={previewLoading}>
      {previewOpen && preview ? 'Refresh preview' : 'Preview today’s email'}
    </Button>
    <Form action={alerts.testEmail()} options={testOptions}>
      {#snippet children({ processing })}
        <Button type="submit" variant="secondary" disabled={processing || testRemaining > 0}>
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
