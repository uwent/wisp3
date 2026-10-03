<script lang="ts">
  import { Form, Link } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import TextField from '@/lib/components/TextField.svelte'
  import { fieldGroups, setup } from '@/routes'
  import type { FieldGroup } from '@/types/serializers'

  import FieldPicker from '@/lib/components/FieldPicker.svelte'

  type Choice = { id: number; name: string; pivot_name: string; farm_name: string }
  let { field_groups, fields }: { field_groups: FieldGroup[]; fields: Choice[] } = $props()

  const names = (ids: number[]) => fields.filter((f) => ids.includes(f.id)).map((f) => f.name).join(', ')
</script>

<svelte:head><title>Field groups · WISP</title></svelte:head>

<div>
  <Link href={setup.show()} class="text-sm text-brand-600 hover:underline">← Setup</Link>
  <h1 class="text-2xl font-semibold">Field groups</h1>
  <p class="max-w-2xl text-sm text-ink-muted">
    Fields that share readings, such as one rain gauge for several fields. Values entered for a group apply to each of
    its fields, unless the field has its own entry or pivot irrigation for that day.
  </p>
</div>

{#if field_groups.length}
  <ul class="divide-y divide-line rounded-lg border border-line bg-surface-raised">
    {#each field_groups as group (group.id)}
      <li class="flex flex-wrap items-center justify-between gap-2 px-4 py-3">
        <div>
          <Link href={fieldGroups.show(group.id)} class="font-medium hover:underline">{group.name}</Link>
          <p class="text-xs text-ink-muted">{names(group.field_ids) || 'No fields'}</p>
        </div>
        <Link href={fieldGroups.show(group.id)} class="text-sm text-brand-600 hover:underline">Enter values</Link>
      </li>
    {/each}
  </ul>
{/if}

<section class="space-y-4 rounded-lg border border-line bg-surface-raised p-6">
  <h2 class="text-lg font-medium">New field group</h2>
  {#if fields.length === 0}
    <p class="text-sm text-ink-muted">Add fields in setup first.</p>
  {:else}
    <Form action={fieldGroups.create()} class="space-y-4" resetOnSuccess>
      {#snippet children({ errors, processing })}
        <TextField label="Name" name="field_group[name]" placeholder="e.g. Home rain gauge" error={errors.name} required />
        <FieldPicker {fields} name="field_group[field_ids][]" />
        <Button type="submit" disabled={processing}>Create group</Button>
      {/snippet}
    </Form>
  {/if}
</section>
