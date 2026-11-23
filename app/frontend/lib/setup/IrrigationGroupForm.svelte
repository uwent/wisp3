<script lang="ts">
  import { Form } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import FieldLabel from '@/lib/components/FieldLabel.svelte'
  import FormFooter from '@/lib/components/FormFooter.svelte'
  import TextField from '@/lib/components/TextField.svelte'
  import { systemName } from '@/lib/geo'
  import { irrigationGroups } from '@/routes'
  import type { Farm, IrrigationGroup } from '@/types/serializers'

  // Add an irrigation group on a farm, or edit one (Setup's dialog): its name,
  // which of the farm's systems share its rain gauge, and which rain their balances use (Q7). A
  // system is in one group at most.
  let {
    farm,
    group,
    ondone,
    ondelete,
  }: {
    farm: Farm
    group?: IrrigationGroup
    ondone: () => void
    /** Deletes the group (asking first); left out for a new group or someone who may not (mayDelete) */
    ondelete?: () => void
  } = $props()

  // The farm's rainfall setting, which a group follows unless it has its own
  const rainSetting = $derived(group?.use_model_precip == null ? '' : String(group.use_model_precip))
  // [value, label, hint]: blank follows the operation
  const rainOptions = $derived([
    ['', `The farm's setting (${farm.use_model_precip ? 'modeled rain' : 'only the rain you enter'})`, null],
    ['true', 'Modeled rain', 'Your gauge readings replace it on the days you enter them.'],
    [
      'false',
      'Only the rain you enter',
      'Best if you read the gauge every day it rains. Days without an entry count as dry. The projection still uses the forecast rain, and also shows what happens if none falls.',
    ],
  ] as const)
</script>

<Form
  action={group ? irrigationGroups.update(group.id) : irrigationGroups.create()}
  class="space-y-4"
  options={{ preserveScroll: true, preserveState: true }}
  onSuccess={ondone}
>
  {#snippet children({ errors, processing })}
    {#if !group}<input type="hidden" name="irrigation_group[farm_id]" value={farm.id} />{/if}
    <TextField
      label="Group name"
      name="irrigation_group[name]"
      value={group?.name ?? ''}
      placeholder="e.g. East half"
      info="irrigation_group.name"
      error={errors.name}
      required
    />
    <fieldset class="space-y-1">
      <legend class="text-sm font-medium">Irrigation systems in this group</legend>
      <input type="hidden" name="irrigation_group[system_ids][]" value="" />
      {#each farm.systems as system (system.id)}
        {@const other = farm.irrigation_groups.find((g) => g.id === system.irrigation_group_id && g.id !== group?.id)}
        <label class="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            class="rounded"
            name="irrigation_group[system_ids][]"
            value={system.id}
            checked={group !== undefined && system.irrigation_group_id === group.id}
          />
          {systemName(system)}
          {#if other}<span class="text-xs text-ink-muted">{`(now in ${other.name})`}</span>{/if}
        </label>
      {/each}
      <p class="text-xs text-ink-muted">A system is in one group at most; checking it here moves it.</p>
    </fieldset>
    <fieldset class="space-y-2" aria-labelledby="irrigation-group-rainfall">
      <FieldLabel as="legend" label="Rainfall" labelId="irrigation-group-rainfall" info="irrigation_group.rainfall" />
      {#each rainOptions as [value, label, hint] (value)}
        <label class="flex items-start gap-3 text-sm">
          <input
            type="radio"
            name="irrigation_group[use_model_precip]"
            {value}
            checked={rainSetting === value}
            class="mt-0.5"
          />
          <span
            >{label}{#if hint}<span class="block text-ink-muted">{hint}</span>{/if}</span
          >
        </label>
      {/each}
      <p class="text-xs text-ink-muted">
        This only changes which rain the balance uses. Nothing is copied or deleted, so you can switch back at any time.
      </p>
    </fieldset>
    <FormFooter {ondelete} deleteLabel="Delete this group">
      <Button type="submit" disabled={processing}>Save</Button>
    </FormFooter>
  {/snippet}
</Form>
