<script lang="ts">
  import { Form } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import FieldLabel from '@/lib/components/FieldLabel.svelte'
  import FormFooter from '@/lib/components/FormFooter.svelte'
  import TextField from '@/lib/components/TextField.svelte'
  import { farms as farmRoutes } from '@/routes'
  import type { Farm } from '@/types/serializers'

  // Add a farm, or edit one (Setup's dialog): its name, notes and rainfall setting (Q7), which its
  // irrigation groups follow unless they have their own
  let {
    farm,
    ondone,
    ondelete,
  }: {
    farm?: Farm
    ondone: () => void
    /** Deletes the farm (asking first); left out for a new farm or someone who isn't an owner */
    ondelete?: () => void
  } = $props()
</script>

<Form
  action={farm ? farmRoutes.update(farm.id) : farmRoutes.create()}
  class="space-y-4"
  options={{ preserveScroll: true, preserveState: true }}
  onSuccess={ondone}
>
  {#snippet children({ errors, processing })}
    <TextField
      label="Farm name"
      name="farm[name]"
      value={farm?.name ?? ''}
      info="farm.name"
      error={errors.name}
      required
    />
    <div class="space-y-1">
      <FieldLabel label="Notes" for="farm-notes" optional />
      <textarea id="farm-notes" name="farm[notes]" rows="2" class="block w-full rounded-md text-sm"
        >{farm?.notes ?? ''}</textarea
      >
    </div>
    <fieldset class="space-y-2" aria-labelledby="farm-rainfall">
      <FieldLabel as="legend" label="Rainfall" labelId="farm-rainfall" info="farm.rainfall" />
      <label class="flex items-start gap-3 text-sm">
        <input
          type="radio"
          name="farm[use_model_precip]"
          value="true"
          checked={farm?.use_model_precip ?? true}
          class="mt-0.5"
        />
        <span>
          Modeled rain for each irrigation system's location
          <span class="block text-ink-muted">Your own gauge readings replace it on the days you enter them.</span>
        </span>
      </label>
      <label class="flex items-start gap-3 text-sm">
        <input
          type="radio"
          name="farm[use_model_precip]"
          value="false"
          checked={farm ? !farm.use_model_precip : false}
          class="mt-0.5"
        />
        <span>Only the rain you enter</span>
      </label>
      <p class="text-xs text-ink-muted">
        An irrigation group can have its own setting. The forecast's rain counts in the days ahead either way.
      </p>
    </fieldset>
    <FormFooter {ondelete} deleteLabel="Delete this farm">
      <Button type="submit" disabled={processing}>Save</Button>
    </FormFooter>
  {/snippet}
</Form>
