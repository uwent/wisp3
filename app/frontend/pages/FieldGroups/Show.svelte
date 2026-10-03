<script lang="ts">
  import { Form, Link, page, router } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import EditableCell from '@/lib/components/EditableCell.svelte'
  import TextField from '@/lib/components/TextField.svelte'
  import { formatDate } from '@/lib/dates'
  import { save } from '@/lib/save'
  import { parseNumber, units as unitsFor } from '@/lib/units'
  import { fieldGroupDays, fieldGroups } from '@/routes'
  import type { FieldGroup } from '@/types/serializers'

  import FieldPicker from '@/lib/components/FieldPicker.svelte'

  type Choice = { id: number; name: string; pivot_name: string; farm_name: string }
  type Day = { date: string; rain_in: number | null; irrigation_in: number | null; soil_moisture_pct: number | null; notes: string | null }

  let { field_group, fields, year, days }: { field_group: FieldGroup; fields: Choice[]; year: number; days: Day[] } = $props()

  const units = $derived(unitsFor(page.props.auth.user?.unit_system))
  const rows = $derived([...days].reverse())
  let editingMembers = $state(false)

  type Column = 'rain_in' | 'irrigation_in' | 'soil_moisture_pct' | 'notes'

  const text = (day: Day, column: Column) =>
    column === 'notes'
      ? (day.notes ?? '')
      : column === 'soil_moisture_pct'
        ? (day.soil_moisture_pct?.toString() ?? '')
        : units.input('depth', day[column])

  async function saveCell(day: Day, column: Column, input: string) {
    let value: number | string | null = input.trim() || null
    if (column !== 'notes') {
      const parsed = column === 'soil_moisture_pct' ? parseNumber(input) : units.parse('depth', input)
      if (!parsed.ok) return parsed.error
      value = parsed.value
    }
    return save(fieldGroupDays.update({ fieldGroupId: field_group.id, date: day.date }), { day: { [column]: value } })
  }

  function destroy() {
    if (confirm(`Delete ${field_group.name} and its entries? The fields themselves stay.`)) {
      router.delete(fieldGroups.destroy(field_group.id).url)
    }
  }

  const COLUMNS: [Column, string][] = [
    ['rain_in', 'Rain'],
    ['irrigation_in', 'Irrigation'],
    ['soil_moisture_pct', 'Moisture reading'],
    ['notes', 'Notes'],
  ]
</script>

<svelte:head><title>{field_group.name} · WISP</title></svelte:head>

<div class="flex flex-wrap items-end justify-between gap-3">
  <div>
    <Link href={fieldGroups.index()} class="text-sm text-brand-600 hover:underline">← Field groups</Link>
    <h1 class="text-2xl font-semibold">{field_group.name}</h1>
    <p class="text-sm text-ink-muted">
      {fields.filter((f) => field_group.field_ids.includes(f.id)).map((f) => f.name).join(', ') || 'No fields yet'}
    </p>
  </div>
  <div class="flex flex-wrap items-center gap-2">
    <select class="rounded-md text-sm" aria-label="Season" value={year} onchange={(e) => router.get(fieldGroups.show(field_group.id).url, { year: e.currentTarget.value })}>
      {#each [year - 2, year - 1, year, year + 1] as y (y)}<option value={y}>{y}</option>{/each}
    </select>
    <Button variant="secondary" onclick={() => (editingMembers = !editingMembers)}>{editingMembers ? 'Close' : 'Edit group'}</Button>
    <Button variant="danger-ghost" onclick={destroy}>Delete</Button>
  </div>
</div>

{#if editingMembers}
  <section class="rounded-lg border border-line bg-surface-raised p-6">
    <Form action={fieldGroups.update(field_group.id)} class="space-y-4" options={{ preserveScroll: true }} onSuccess={() => (editingMembers = false)}>
      {#snippet children({ errors, processing })}
        <TextField label="Name" name="field_group[name]" value={field_group.name} error={errors.name} required />
        <FieldPicker {fields} selected={field_group.field_ids} name="field_group[field_ids][]" />
        <Button type="submit" disabled={processing}>Save</Button>
      {/snippet}
    </Form>
  </section>
{/if}

<p class="text-xs text-ink-muted">
  Click a cell to enter a value for every field in the group; Enter saves and moves down. Depths in {units.label('depth')}.
</p>
<div class="max-h-[40rem] overflow-auto rounded-lg border border-line bg-surface-raised">
  <table class="w-full text-sm">
    <thead class="sticky top-0 z-10 border-b border-line bg-surface-raised text-xs text-ink-muted">
      <tr class="text-right">
        <th class="px-3 py-2 text-left font-medium">Date</th>
        {#each COLUMNS as [column, label] (column)}
          <th class="px-2 py-2 font-medium {column === 'notes' ? 'text-left' : ''}">{label}{column === 'soil_moisture_pct' ? ' (%)' : ''}</th>
        {/each}
      </tr>
    </thead>
    <tbody class="divide-y divide-line">
      {#each rows as day, row (day.date)}
        <tr>
          <th scope="row" class="px-3 py-1 text-left font-normal whitespace-nowrap">{formatDate(day.date, { weekday: true })}</th>
          {#each COLUMNS as [column, label], col (column)}
            <td class="px-1 py-0.5">
              <EditableCell
                grid="group-days"
                {row}
                {col}
                align={column === 'notes' ? 'left' : 'right'}
                text={text(day, column)}
                label="{label}, {formatDate(day.date, { weekday: true })}"
                onsave={(input) => saveCell(day, column, input)}
              >
                {#if column === 'notes'}<span class="block max-w-64 truncate text-ink-muted">{day.notes ?? ''}&nbsp;</span>
                {:else if day[column] === null}<span class="text-ink-muted">–</span>
                {:else if column === 'soil_moisture_pct'}{day.soil_moisture_pct}
                {:else}{units.format('depth', day[column], { unit: false })}{/if}
              </EditableCell>
            </td>
          {/each}
        </tr>
      {/each}
    </tbody>
  </table>
</div>
