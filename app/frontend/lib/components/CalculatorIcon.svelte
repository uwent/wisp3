<script lang="ts">
  // A calculator, for the irrigation calculator's buttons. Decorative: the button names itself.
  let { class: className = 'size-4' }: { class?: string } = $props()
</script>

<svg viewBox="0 0 20 20" class={className} fill="none" stroke="currentColor" stroke-width="1.5" aria-hidden="true">
  <rect x="4" y="2.5" width="12" height="15" rx="1.5" />
  <rect x="6.5" y="5" width="7" height="3" rx="0.5" />
  <path d="M7 11h.01M10 11h.01M13 11h.01M7 14h.01M10 14h.01M13 14h.01" stroke-width="2" stroke-linecap="round" />
</svg>
