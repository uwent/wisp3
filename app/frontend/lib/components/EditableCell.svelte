<script lang="ts">
  import type { Snippet } from 'svelte'
  import { tick } from 'svelte'

  // A spreadsheet-style cell. Click, Enter or start typing to edit; Enter saves and moves down,
  // Tab saves and moves on, Escape cancels; arrow keys move between cells of the same grid.
  // onsave gets the typed text and resolves with an error message, or null once saved.
  let {
    text,
    label,
    grid,
    row,
    col,
    onsave,
    children,
    align = 'right',
    class: className = '',
  }: {
    text: string
    label: string
    grid: string
    row: number
    col: number
    onsave: (text: string) => Promise<string | null>
    children: Snippet
    align?: 'left' | 'right'
    class?: string
  } = $props()

  let editing = $state(false)
  let draft = $state('')
  let error = $state<string | null>(null)
  let saving = $state(false)
  let input: HTMLInputElement | undefined = $state()

  const cellAt = (r: number, c: number) =>
    document.querySelector<HTMLButtonElement>(`[data-grid="${grid}"][data-row="${r}"][data-col="${c}"]`)

  async function start(initial?: string) {
    draft = initial ?? text
    error = null
    editing = true
    await tick()
    input?.focus()
    if (initial === undefined) input?.select()
  }

  async function commit(move?: 'down') {
    // Chromium blurs an input as it's removed, so a cancelled or finished edit can arrive here too
    if (saving || !editing) return
    if (draft.trim() === text.trim()) {
      editing = false
      if (move) cellAt(row + 1, col)?.click()
      return
    }
    saving = true
    error = await onsave(draft)
    saving = false
    if (error) {
      input?.focus()
      return
    }
    editing = false
    if (move) {
      await tick()
      cellAt(row + 1, col)?.click()
    }
  }

  function onInputKey(event: KeyboardEvent) {
    if (event.key === 'Enter') {
      event.preventDefault()
      commit('down')
    } else if (event.key === 'Escape') {
      event.preventDefault()
      editing = false
      error = null
      cellAt(row, col)?.focus()
    }
  }

  function onCellKey(event: KeyboardEvent) {
    const moves: Record<string, [number, number]> = {
      ArrowUp: [-1, 0],
      ArrowDown: [1, 0],
      ArrowLeft: [0, -1],
      ArrowRight: [0, 1],
    }
    const move = moves[event.key]
    if (move) {
      event.preventDefault()
      cellAt(row + move[0], col + move[1])?.focus()
    } else if (event.key === 'Enter' || event.key === 'F2') {
      event.preventDefault()
      start()
    } else if (event.key === 'Delete' || event.key === 'Backspace') {
      event.preventDefault()
      start('')
    } else if (event.key.length === 1 && !event.ctrlKey && !event.metaKey && !event.altKey) {
      event.preventDefault()
      start(event.key)
    }
  }
</script>

{#if editing}
  <!-- The cell's content stays in place, unseen, so the column keeps its width while the input
       covers it; otherwise the table shifts as an edit opens and closes, and a click meant for the
       next cell lands somewhere else -->
  <div class="relative">
    <span aria-hidden="true" class="invisible block min-w-16 px-1.5 py-1 tabular-nums">{@render children()}</span>
    <input
      bind:this={input}
      bind:value={draft}
      onkeydown={onInputKey}
      onblur={() => commit()}
      aria-label={label}
      aria-invalid={error ? 'true' : undefined}
      disabled={saving}
      class="absolute inset-0 size-full min-w-0 rounded border-brand-500 px-1.5 py-0 text-sm tabular-nums focus:ring-brand-500
        {align === 'right' ? 'text-right' : 'text-left'}
        {error ? 'border-status-irrigate' : ''}"
    />
    {#if error}
      <p
        role="alert"
        class="absolute top-full right-0 z-10 mt-1 w-max max-w-56 rounded bg-status-irrigate px-2 py-1 text-xs text-white shadow"
      >
        {error}
      </p>
    {/if}
  </div>
{:else}
  <button
    type="button"
    data-grid={grid}
    data-row={row}
    data-col={col}
    aria-label={label}
    onclick={() => start()}
    onkeydown={onCellKey}
    class="block w-full min-w-16 rounded px-1.5 py-1 tabular-nums hover:bg-brand-50
      {align === 'right' ? 'text-right' : 'text-left'}
      focus-visible:outline-2 focus-visible:outline-brand-500 {className}"
  >
    {@render children()}
  </button>
{/if}
