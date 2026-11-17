<script lang="ts">
  import type { Snippet } from 'svelte'
  import type { HTMLButtonAttributes } from 'svelte/elements'

  type Variant = 'primary' | 'secondary' | 'danger' | 'ghost' | 'danger-ghost'

  let {
    variant = 'primary',
    type = 'button',
    class: className = '',
    children,
    ...rest
  }: HTMLButtonAttributes & { variant?: Variant; children: Snippet } = $props()

  // Hover only while enabled: a disabled button (its own, or its fieldset's) stays as it is
  const variants: Record<Variant, string> = {
    primary: 'bg-brand-600 text-white enabled:hover:bg-brand-700 dark:text-surface',
    secondary: 'border border-line bg-surface-raised text-ink enabled:hover:bg-surface',
    danger: 'bg-status-irrigate text-white enabled:hover:opacity-90',
    ghost: 'text-brand-600 enabled:hover:bg-brand-50',
    'danger-ghost': 'text-status-irrigate-ink enabled:hover:bg-status-irrigate/10',
  }
</script>

<button
  {type}
  class="inline-flex items-center justify-center gap-2 rounded-md px-4 py-2 text-sm font-medium transition
    focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-500
    disabled:cursor-not-allowed disabled:opacity-60 {variants[variant]} {className}"
  {...rest}
>
  {@render children()}
</button>
