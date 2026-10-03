<script lang="ts">
  // Checkboxes for choosing fields (e.g. a field group's members), grouped by farm and pivot
  type Choice = { id: number; name: string; pivot_name: string; farm_name: string }
  let { fields, selected = [], name }: { fields: Choice[]; selected?: number[]; name: string } = $props()

  const byPivot = $derived(
    Object.entries(Object.groupBy(fields, (field) => `${field.farm_name} · ${field.pivot_name}`)) as [string, Choice[]][],
  )
</script>

<fieldset class="space-y-3">
  <legend class="text-sm font-medium">Fields</legend>
  <input type="hidden" {name} value="" />
  {#each byPivot as [pivot, choices] (pivot)}
    <div>
      <p class="text-xs text-ink-muted">{pivot}</p>
      <div class="mt-1 flex flex-wrap gap-x-5 gap-y-1">
        {#each choices as field (field.id)}
          <label class="flex items-center gap-2 text-sm">
            <input type="checkbox" class="rounded" {name} value={field.id} checked={selected.includes(field.id)} />
            {field.name}
          </label>
        {/each}
      </div>
    </div>
  {/each}
</fieldset>
