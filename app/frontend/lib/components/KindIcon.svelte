<script lang="ts">
  import type { PivotKind } from '@/lib/geo'
  import { GLYPH_PATHS, KIND_GLYPHS } from '@/lib/map/glyphs'

  // An irrigation system's kind as its map glyph (G.14): a pivot's circle, a traveler's diamond.
  // Decorative beside the kind's name; give it a label where it stands alone.
  let { kind, size = 14, label }: { kind: PivotKind; size?: number; label?: string } = $props()
</script>

<svg
  viewBox="-2 -2 28 28"
  width={size}
  height={size}
  class="inline-block shrink-0 align-[-0.125em]"
  role={label ? 'img' : undefined}
  aria-label={label}
  aria-hidden={label ? undefined : 'true'}
>
  <path
    d={GLYPH_PATHS[KIND_GLYPHS[kind]]}
    class="fill-map-system-ink/30 stroke-map-system-ink"
    stroke-width="2.5"
    stroke-linejoin="round"
  />
</svg>
