<script lang="ts">
  import { Form } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import FieldLabel from '@/lib/components/FieldLabel.svelte'
  import FormFooter from '@/lib/components/FormFooter.svelte'
  import TextField from '@/lib/components/TextField.svelte'
  import { farms as farmRoutes } from '@/routes'
  import type { Farm } from '@/types/serializers'

  // Add a farm, or edit one (Setup's dialog)
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
    <FormFooter {ondelete} deleteLabel="Delete this farm">
      <Button type="submit" disabled={processing}>Save</Button>
    </FormFooter>
  {/snippet}
</Form>
