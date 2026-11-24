<script lang="ts">
  import { Form, router } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import { addDays, formatDate } from '@/lib/dates'
  import { plantingCutting, plantingCuttings } from '@/routes'
  import type { Planting } from '@/types/serializers'

  // A perennial's cuttings on its page: each restarts its canopy. readOnly:
  // time travelling, nothing added or removed
  let { planting, readOnly }: { planting: Planting; readOnly: boolean } = $props()
</script>

<!-- A perennial's cuttings: each restarts its canopy -->
<section class="space-y-3 rounded-lg border border-line bg-surface-raised p-4" aria-labelledby="cuttings-heading">
  <div>
    <h2 id="cuttings-heading" class="font-medium">Cuttings</h2>
    <p class="text-sm text-ink-muted">
      Each cutting drops the canopy to stubble that day, and it regrows from there on the perennial curve, corrected by
      the readings you enter after it.
    </p>
  </div>
  {#if planting.cuttings.length}
    <ul class="flex flex-wrap gap-2 text-sm" aria-label="Cuttings">
      {#each planting.cuttings as cutting (cutting.id)}
        <li class="flex items-center gap-2 rounded-md border border-line px-2.5 py-1">
          Cut {formatDate(cutting.date, { weekday: true })}
          {#if !readOnly}
            <button
              type="button"
              class="text-xs text-status-irrigate-ink hover:underline"
              aria-label="Remove the {formatDate(cutting.date)} cutting"
              onclick={() => {
                if (confirm(`Remove the ${formatDate(cutting.date)} cutting?`))
                  router.delete(plantingCutting({ plantingId: planting.id, id: cutting.id }).url, {
                    preserveScroll: true,
                  })
              }}
            >
              Remove
            </button>
          {/if}
        </li>
      {/each}
    </ul>
  {:else}
    <p class="text-sm text-ink-muted">No cuttings yet this season.</p>
  {/if}
  {#if !readOnly}
    <Form
      action={plantingCuttings(planting.id)}
      class="flex flex-wrap items-end gap-2"
      options={{ preserveScroll: true }}
      resetOnSuccess
    >
      {#snippet children({ errors, processing })}
        <div class="space-y-1">
          <label for="cutting-date" class="block text-sm font-medium">Cut on</label>
          <input
            id="cutting-date"
            type="date"
            name="cutting[date]"
            required
            min={addDays(planting.emergence_date, 1)}
            max={planting.end_date}
            class="block rounded-md text-sm"
          />
        </div>
        <Button type="submit" variant="secondary" disabled={processing}>Add cutting</Button>
        {#if errors.date || errors.base}<p class="w-full text-sm text-status-irrigate-ink">
            {errors.date ?? errors.base}
          </p>{/if}
      {/snippet}
    </Form>
  {/if}
</section>
