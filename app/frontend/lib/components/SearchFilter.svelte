<script lang="ts">
  import { searchHighlight } from '@/lib/searchHighlight'

  // The name and crop search box over a list of fields (lib/search.ts): the dashboard, Setup and
  // the map's list, marking what it matched on the page. As tall as the selects beside it; compact
  // in the map's sidebar.
  let {
    value = $bindable(''),
    placeholder = 'Search fields, crops, systems or farms',
    label = 'Search fields',
    compact = false,
    class: className = '',
  }: { value?: string; placeholder?: string; label?: string; compact?: boolean; class?: string } = $props()
</script>

<input
  type="search"
  bind:value
  {placeholder}
  aria-label={label}
  {@attach searchHighlight(() => value)}
  class="block rounded-md text-sm {compact ? 'py-1' : ''} {className}"
/>
