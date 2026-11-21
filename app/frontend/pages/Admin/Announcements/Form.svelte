<script lang="ts">
  import { Form, Link, http, router } from '@inertiajs/svelte'
  import { untrack } from 'svelte'

  import AdminTabs from '@/lib/components/AdminTabs.svelte'
  import Button from '@/lib/components/Button.svelte'
  import FieldLabel from '@/lib/components/FieldLabel.svelte'
  import FormFooter from '@/lib/components/FormFooter.svelte'
  import TextField from '@/lib/components/TextField.svelte'
  import { type Edit, insert, link, prefixLines, wrap } from '@/lib/markdownEdit'
  import { confirmUnsavedChanges } from '@/lib/unsaved.svelte'
  import { adminAnnouncements } from '@/routes'
  import type { AdminAnnouncement } from '@/types/serializers'

  type Audience = {
    key: AdminAnnouncement['audience']
    label: string
    description: string
    dated: boolean
    count: number
  }

  let {
    announcement,
    audience_date,
    audiences,
    placeholders,
  }: {
    announcement: AdminAnnouncement | null
    audience_date: string
    audiences: Audience[]
    placeholders: { key: string; description: string }[]
  } = $props()

  const editing = $derived(announcement !== null)
  const title = $derived(editing ? 'Edit announcement' : 'New announcement')

  let subject = $state(untrack(() => announcement?.subject ?? ''))
  let body = $state(untrack(() => announcement?.body ?? ''))
  let audience = $state<Audience['key']>(untrack(() => announcement?.audience ?? 'all'))
  let date = $state(untrack(() => audience_date))
  let textarea = $state<HTMLTextAreaElement>()

  const chosen = $derived(audiences.find((a) => a.key === audience))

  // The counts for another date, without leaving the page
  let countedDate = untrack(() => audience_date)
  function recount() {
    if (!date || date === countedDate) return
    countedDate = date
    router.reload({ only: ['audiences'], data: { date } })
  }

  let edited = $state(false)
  let saved = $state(false)
  confirmUnsavedChanges(
    () => !saved && edited,
    () => document.getElementById('announcement-form'),
  )

  // The toolbar: Markdown put into the message, the textarea keeping its focus and selection
  function apply(make: (text: string, start: number, end: number) => Edit) {
    if (!textarea) return
    const edit = make(body, textarea.selectionStart, textarea.selectionEnd)
    body = edit.text
    edited = true
    const element = textarea
    requestAnimationFrame(() => {
      element.focus()
      element.setSelectionRange(edit.start, edit.end)
    })
  }

  const tools: { label: string; class?: string; make: (t: string, s: number, e: number) => Edit }[] = [
    { label: 'Bold', class: 'font-bold', make: (t, s, e) => wrap(t, s, e, '**', '**', 'bold text') },
    { label: 'Italic', class: 'italic', make: (t, s, e) => wrap(t, s, e, '*', '*', 'italic text') },
    { label: 'Link', make: link },
    { label: 'Heading', make: (t, s, e) => prefixLines(t, s, e, '## ') },
    { label: 'Bulleted list', make: (t, s, e) => prefixLines(t, s, e, '- ') },
    { label: 'Numbered list', make: (t, s, e) => prefixLines(t, s, e, '', true) },
  ]

  // The email as it would be sent, rendered by the server a moment after typing stops
  let preview = $state<{ subject: string; html: string; errors: string[] } | null>(null)
  let previewError = $state(false)
  let controller: AbortController | undefined
  $effect(() => {
    const data = { announcement: { subject, body } }
    const timer = setTimeout(async () => {
      controller?.abort()
      const own = (controller = new AbortController())
      try {
        const response = await http.getClient().request({
          method: 'post',
          url: adminAnnouncements.preview().url,
          data,
          signal: own.signal,
        })
        preview = JSON.parse(response.data)
        previewError = false
      } catch {
        if (!own.signal.aborted) previewError = true
      }
    }, 400)
    return () => clearTimeout(timer)
  })

  function destroy() {
    if (!announcement || !confirm("Delete this draft? This can't be undone.")) return
    saved = true
    router.delete(adminAnnouncements.destroy(announcement.id).url, { onFinish: () => (saved = false) })
  }

  const people = (n: number) => `${n.toLocaleString()} ${n === 1 ? 'person' : 'people'}`
</script>

<svelte:head><title>{title} · WISP</title></svelte:head>

<AdminTabs />

<div class="space-y-4">
  <div>
    <Link href={adminAnnouncements.index()} class="text-sm text-brand-600 hover:underline">← Announcements</Link>
    <h1 class="text-2xl font-semibold">{title}</h1>
    <p class="text-sm text-ink-muted">
      Saved as a draft. On the next page you can send yourself a test, then send it to the audience.
    </p>
  </div>

  <div class="grid items-start gap-6 lg:grid-cols-2">
    <Form
      id="announcement-form"
      action={announcement ? adminAnnouncements.update(announcement.id) : adminAnnouncements.create()}
      class="space-y-6 rounded-lg border border-line bg-surface-raised p-6"
      onSuccess={() => (saved = true)}
    >
      {#snippet children({ errors, processing })}
        <div class="space-y-6" oninput={() => (edited = true)} onchange={() => (edited = true)}>
          <TextField
            label="Subject"
            name="announcement[subject]"
            bind:value={subject}
            error={errors.subject}
            required
          />

          <fieldset class="space-y-2">
            <legend class="text-sm font-medium">Send to</legend>
            {#each audiences as option (option.key)}
              <label class="flex items-start gap-3 text-sm">
                <input
                  type="radio"
                  name="announcement[audience]"
                  value={option.key}
                  bind:group={audience}
                  class="mt-0.5"
                />
                <span
                  ><span class="font-medium">{option.label}</span>
                  <span class="text-ink-muted">{` · ${people(option.count)}`}</span>
                  <span class="block text-ink-muted">{option.description}</span></span
                >
              </label>
            {/each}
            {#if chosen?.dated}
              <div class="max-w-48 space-y-1 pt-1 pl-7">
                <label for="audience-date" class="block text-sm font-medium">Date</label>
                <input
                  id="audience-date"
                  type="date"
                  name="announcement[audience_date]"
                  bind:value={date}
                  onchange={recount}
                  onblur={recount}
                  required
                  class="block w-full rounded-md text-sm"
                />
                {#if errors.audience_date}<p class="text-sm text-status-irrigate-ink">{errors.audience_date}</p>{/if}
              </div>
            {/if}
            <p class="text-sm text-ink-muted">
              Unconfirmed accounts, those that unsubscribed from announcements and example addresses are left out.
            </p>
          </fieldset>

          <div class="space-y-1">
            <FieldLabel label="Message" for="announcement-body" />
            <div role="toolbar" aria-label="Formatting" aria-controls="announcement-body" class="flex flex-wrap gap-1">
              {#each tools as tool (tool.label)}
                <button
                  type="button"
                  class="rounded border border-line px-2 py-0.5 text-sm hover:bg-surface {tool.class ?? ''}"
                  onclick={() => apply(tool.make)}>{tool.label}</button
                >
              {/each}
            </div>
            <textarea
              id="announcement-body"
              name="announcement[body]"
              rows="16"
              bind:this={textarea}
              bind:value={body}
              required
              aria-invalid={errors.body ? 'true' : undefined}
              aria-describedby={errors.body ? 'announcement-body-error' : 'announcement-body-hint'}
              class="block w-full rounded-md text-sm {errors.body ? 'border-status-irrigate' : ''}"></textarea>
            {#if errors.body}
              <p id="announcement-body-error" class="text-sm text-status-irrigate-ink">{errors.body}</p>
            {/if}
            <p id="announcement-body-hint" class="text-sm text-ink-muted">
              Markdown: **bold**, *italic*, [text](https://…), ## Heading, - list. A blank line starts a new paragraph;
              web addresses become links.
            </p>
          </div>

          <div class="space-y-2">
            <h2 class="text-sm font-medium">Placeholders</h2>
            <p class="text-sm text-ink-muted">
              Filled in for each person. Give a fallback after a bar for accounts without one, as in
              <code class="rounded bg-surface px-1">{'{{first_name|there}}'}</code>. They work in the subject too.
            </p>
            <ul class="space-y-1 text-sm">
              {#each placeholders as placeholder (placeholder.key)}
                <li class="flex flex-wrap items-baseline gap-2">
                  <button
                    type="button"
                    class="rounded border border-line px-2 py-0.5 font-mono text-xs hover:bg-surface"
                    aria-label="Insert {placeholder.description.toLowerCase()} placeholder"
                    onclick={() => apply((t, s, e) => insert(t, s, e, `{{${placeholder.key}}}`))}
                    >{`{{${placeholder.key}}}`}</button
                  >
                  <span class="text-ink-muted">{placeholder.description}</span>
                </li>
              {/each}
            </ul>
          </div>

          <FormFooter ondelete={announcement ? destroy : undefined} deleteLabel="Delete draft">
            <Button type="submit" disabled={processing}>Save draft</Button>
          </FormFooter>
        </div>
      {/snippet}
    </Form>

    <section aria-labelledby="preview-heading" class="space-y-2 lg:sticky lg:top-4">
      <h2 id="preview-heading" class="text-lg font-medium">Preview</h2>
      <p class="text-sm text-ink-muted">As you'd get it, with your own name in the placeholders.</p>
      {#if previewError}
        <p class="text-sm text-status-irrigate-ink" role="status">The preview couldn't be updated.</p>
      {/if}
      {#if preview}
        {#each preview.errors as error (error)}
          <p class="rounded-md bg-status-caution/15 px-3 py-2 text-sm">{error}</p>
        {/each}
        <p class="text-sm">
          <span class="text-ink-muted">Subject:</span> <span class="font-medium">{preview.subject}</span>
        </p>
        <iframe
          title="Announcement preview"
          srcdoc={preview.html}
          sandbox="allow-popups"
          class="h-[70vh] w-full rounded-lg border border-line bg-white"
        ></iframe>
      {/if}
    </section>
  </div>
</div>
