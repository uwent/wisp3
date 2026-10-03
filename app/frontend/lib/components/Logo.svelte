<script lang="ts">
  let { class: className = '' }: { class?: string } = $props()
</script>

<span class="inline-flex items-center gap-2 font-display font-semibold tracking-tight {className}">
  <img src="/icon.svg" alt="" class="size-7" />
  <span>WISP</span>
</span>
