<script lang="ts">
  import { Form } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import FormFooter from '@/lib/components/FormFooter.svelte'
  import TextField from '@/lib/components/TextField.svelte'
  import { systemName } from '@/lib/geo'
  import { pivotGroups } from '@/routes'
  import type { Farm, PivotGroup } from '@/types/serializers'

  // Add an irrigation group on a farm, or edit one (PLAN.md Phase 8 G.4; Setup's dialog): its name and
  // which of the farm's systems share its rain gauge. A system is in one group at most.
  let {
    farm,
    group,
    ondone,
    ondelete,
  }: {
    farm: Farm
    group?: PivotGroup
    ondone: () => void
    /** Deletes the group (asking first); left out for a new group or someone who may not (mayDelete) */
    ondelete?: () => void
  } = $props()
</script>

<Form
  action={group ? pivotGroups.update(group.id) : pivotGroups.create()}
  class="space-y-4"
  options={{ preserveScroll: true, preserveState: true }}
  onSuccess={ondone}
>
  {#snippet children({ errors, processing })}
    {#if !group}<input type="hidden" name="pivot_group[farm_id]" value={farm.id} />{/if}
    <TextField
      label="Group name"
      name="pivot_group[name]"
      value={group?.name ?? ''}
      placeholder="e.g. East half"
      info="pivot_group.name"
      error={errors.name}
      required
    />
    <fieldset class="space-y-1">
      <legend class="text-sm font-medium">Irrigation systems in this group</legend>
      <input type="hidden" name="pivot_group[pivot_ids][]" value="" />
      {#each farm.pivots as pivot (pivot.id)}
        {@const other = farm.pivot_groups.find((g) => g.id === pivot.pivot_group_id && g.id !== group?.id)}
        <label class="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            class="rounded"
            name="pivot_group[pivot_ids][]"
            value={pivot.id}
            checked={group !== undefined && pivot.pivot_group_id === group.id}
          />
          {systemName(pivot)}
          {#if other}<span class="text-xs text-ink-muted">{`(now in ${other.name})`}</span>{/if}
        </label>
      {/each}
      <p class="text-xs text-ink-muted">A system is in one group at most; checking it here moves it.</p>
    </fieldset>
    <FormFooter {ondelete} deleteLabel="Delete this group">
      <Button type="submit" disabled={processing}>Save</Button>
    </FormFooter>
  {/snippet}
</Form>
