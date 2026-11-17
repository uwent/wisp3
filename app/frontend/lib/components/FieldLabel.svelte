<script lang="ts">
  import { page } from '@inertiajs/svelte'

  import InfoTip from '@/lib/components/InfoTip.svelte'
  import { fieldInfo, type FieldInfoKey } from '@/lib/fieldInfo'
  import { units } from '@/lib/units'

  // A form control's label with its info tip (G.13) at the far end of the line. The tip sits outside
  // the <label> (a button inside one would focus the control) and outside the text a legend's
  // fieldset is named by (`labelId`), so neither the control's name nor the changes prompt
  // (lib/formChanges.ts) picks up its "About …".
  let {
    label,
    info,
    for: htmlFor,
    as = 'label',
    labelId,
    hidden = false,
    class: className = 'text-sm font-medium',
  }: {
    label: string
    info?: FieldInfoKey
    /** The control's id, for a <label> */
    for?: string | null
    /** A <label>, a <legend> (the fieldset's first child), or a <span> naming a radiogroup */
    as?: 'label' | 'legend' | 'span'
    /** An id for the label's own text, for aria-labelledby */
    labelId?: string
    /** Screen readers only (in table cells); no tip */
    hidden?: boolean
    class?: string
  } = $props()

  const tip = $derived(info ? fieldInfo(info, units(page.props.auth.user?.unit_system)) : null)
</script>

{#if hidden}
  <label for={htmlFor ?? undefined} class="sr-only">{label}</label>
{:else if as === 'legend'}
  <legend class="flex w-full items-center justify-between gap-2 {className}">
    <span id={labelId}>{label}</span>
    {#if tip}<InfoTip text={tip.text} term={tip.term} label="About {label}" />{/if}
  </legend>
{:else}
  <div class="flex items-center justify-between gap-2">
    {#if as === 'label'}
      <label for={htmlFor ?? undefined} id={labelId} class="block {className}">{label}</label>
    {:else}
      <span id={labelId} class="block {className}">{label}</span>
    {/if}
    {#if tip}<InfoTip text={tip.text} term={tip.term} label="About {label}" />{/if}
  </div>
{/if}
