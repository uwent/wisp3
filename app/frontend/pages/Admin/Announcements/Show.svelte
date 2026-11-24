<script lang="ts">
  import { Form, Link, router, usePoll } from '@inertiajs/svelte'

  import AdminTabs from '@/lib/components/AdminTabs.svelte'
  import Button from '@/lib/components/Button.svelte'
  import Dialog from '@/lib/components/Dialog.svelte'
  import { formatTimestamp } from '@/lib/dates'
  import { count } from '@/lib/text'
  import { adminAnnouncements } from '@/routes'
  import type { AdminAnnouncement } from '@/types/serializers'

  let {
    announcement,
    preview,
    recipients_now,
    progress,
    failures,
  }: {
    announcement: AdminAnnouncement
    preview: { subject: string; html: string }
    /** A draft's audience as it stands now */
    recipients_now: number | null
    progress: { pending: number; sent: number; failed: number; skipped: number } | null
    failures: { email: string; error: string | null }[]
  } = $props()

  const draft = $derived(announcement.status === 'draft')
  const sending = $derived(announcement.status === 'sending')
  const total = $derived(announcement.recipients_count ?? 0)
  const done = $derived(progress ? progress.sent + progress.failed + progress.skipped : 0)

  // While it sends, the counts every few seconds
  const poll = usePoll(3000, { only: ['announcement', 'progress', 'failures'] }, { autoStart: false })
  $effect(() => {
    if (sending) poll.start()
    else poll.stop()
  })

  let confirming = $state(false)
  let processing = $state(false)
  function send() {
    router.post(
      adminAnnouncements.deliver(announcement.id).url,
      {},
      {
        onStart: () => (processing = true),
        onFinish: () => {
          processing = false
          confirming = false
        },
      },
    )
  }

  const statusText = $derived(
    {
      draft: 'Draft',
      sending: 'Sending',
      sent: 'Sent',
      incomplete: 'Sent, with failures',
    }[announcement.status],
  )
</script>

<svelte:head><title>{announcement.subject} · Announcements · WISP</title></svelte:head>

<AdminTabs />

<div class="space-y-4">
  <div>
    <Link href={adminAnnouncements.index()} class="text-sm text-brand-600 hover:underline">← Announcements</Link>
    <h1 class="text-2xl font-semibold">{announcement.subject}</h1>
    <p class="text-sm text-ink-muted">
      {statusText}
      {#if draft}
        {` · created ${formatTimestamp(announcement.created_at)}${announcement.created_by ? ` by ${announcement.created_by}` : ''}`}
      {:else if announcement.sent_at}
        {` · started ${formatTimestamp(announcement.sent_at)}${announcement.sent_by ? ` by ${announcement.sent_by}` : ''}`}
      {/if}
    </p>
  </div>

  <section class="space-y-4 rounded-lg border border-line bg-surface-raised p-6">
    <p class="text-sm">
      <span class="text-ink-muted">Audience:</span>
      <span class="font-medium">{announcement.audience_text}</span>
      {#if draft && recipients_now !== null}{` · ${count(recipients_now, 'person', 'people')} now`}{:else if !draft}{` · ${count(total, 'person', 'people')}`}{/if}
    </p>

    {#if draft}
      <div class="flex flex-wrap items-center gap-3">
        <Link
          href={adminAnnouncements.edit(announcement.id)}
          class="rounded-md border border-line bg-surface-raised px-4 py-2 text-sm font-medium hover:bg-surface"
        >
          Edit
        </Link>
        <Form action={adminAnnouncements.test(announcement.id)} options={{ preserveScroll: true }}>
          {#snippet children({ processing: testing })}
            <Button type="submit" variant="secondary" disabled={testing}>Send a test to me</Button>
          {/snippet}
        </Form>
        <Button class="ml-auto" disabled={!recipients_now} onclick={() => (confirming = true)}>
          Send to {count(recipients_now ?? 0, 'person', 'people')}
        </Button>
      </div>
    {:else if progress}
      <div class="space-y-2" role="status">
        <p class="text-sm">
          {#if sending}Sending:
          {/if}{progress.sent.toLocaleString()} of {total.toLocaleString()} sent{progress.failed
            ? `, ${progress.failed} failed`
            : ''}{progress.skipped ? `, ${progress.skipped} skipped (unsubscribed since)` : ''}.
        </p>
        <div class="h-2 overflow-hidden rounded-full bg-line" aria-hidden="true">
          <div
            class="h-full bg-brand-600 transition-[width]"
            style="width: {total ? Math.round((100 * done) / total) : 100}%"
          ></div>
        </div>
      </div>
      {#if announcement.resumable}
        <Form action={adminAnnouncements.resume(announcement.id)} options={{ preserveScroll: true }}>
          {#snippet children({ processing: resuming })}
            <div class="flex flex-wrap items-center gap-3">
              <Button type="submit" variant="secondary" disabled={resuming}>Send to those it missed</Button>
              <span class="text-sm text-ink-muted">
                {sending ? "It's stopped moving, so its worker may have restarted." : 'Tries the failed ones again.'}
              </span>
            </div>
          {/snippet}
        </Form>
      {/if}
      {#if failures.length}
        <div class="space-y-1">
          <h2 class="text-sm font-medium">Failed</h2>
          <ul class="space-y-1 text-sm">
            {#each failures as failure (failure.email)}
              <li><span class="font-medium">{failure.email}</span>{` · ${failure.error ?? ''}`}</li>
            {/each}
          </ul>
        </div>
      {/if}
    {/if}
  </section>

  <section aria-labelledby="preview-heading" class="space-y-2">
    <h2 id="preview-heading" class="text-lg font-medium">The email</h2>
    <p class="text-sm">
      <span class="text-ink-muted">Subject:</span> <span class="font-medium">{preview.subject}</span>
      <span class="text-ink-muted">{' (as you would get it)'}</span>
    </p>
    <iframe
      title="Announcement preview"
      srcdoc={preview.html}
      sandbox="allow-popups"
      class="h-[70vh] w-full rounded-lg border border-line bg-white"
    ></iframe>
  </section>
</div>

<Dialog
  bind:open={confirming}
  title="Send to {count(recipients_now ?? 0, 'person', 'people')}?"
  description="{announcement.audience_text}. It goes out a few a second and can't be stopped or changed once started."
>
  <div class="flex justify-end gap-2">
    <Button variant="secondary" onclick={() => (confirming = false)}>Cancel</Button>
    <Button disabled={processing} onclick={send}>Send now</Button>
  </div>
</Dialog>
