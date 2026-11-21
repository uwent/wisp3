<script lang="ts">
  import { Link } from '@inertiajs/svelte'

  import AdminTabs from '@/lib/components/AdminTabs.svelte'
  import { formatDate } from '@/lib/dates'
  import { adminAnnouncements } from '@/routes'
  import type { AdminAnnouncement } from '@/types/serializers'

  let { announcements }: { announcements: AdminAnnouncement[] } = $props()

  const STATUS: Record<AdminAnnouncement['status'], string> = {
    draft: 'Draft',
    sending: 'Sending',
    sent: 'Sent',
    incomplete: 'Sent, with failures',
  }
</script>

<svelte:head><title>Announcements · WISP</title></svelte:head>

<AdminTabs />

<div class="space-y-4">
  <div class="flex flex-wrap items-end justify-between gap-3">
    <div>
      <h1 class="text-2xl font-semibold">Announcements</h1>
      <p class="text-sm text-ink-muted">
        Emails to everyone or a group of accounts, in WISP's email layout. Replies come to WISP's address. Growers can
        unsubscribe from them without turning off the daily email.
      </p>
    </div>
    <Link
      href={adminAnnouncements.new()}
      class="rounded-md bg-brand-600 px-4 py-2 text-sm font-medium whitespace-nowrap text-white hover:bg-brand-700 dark:text-surface"
      >New announcement</Link
    >
  </div>

  {#if announcements.length}
    <ul class="divide-y divide-line rounded-lg border border-line bg-surface-raised">
      {#each announcements as announcement (announcement.id)}
        <li class="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1 px-4 py-3">
          <div class="min-w-0">
            <Link href={adminAnnouncements.show(announcement.id)} class="font-medium text-brand-600 hover:underline"
              >{announcement.subject}</Link
            >
            <p class="text-sm text-ink-muted">
              {announcement.audience_text}{announcement.recipients_count !== null
                ? ` · ${announcement.recipients_count.toLocaleString()} ${announcement.recipients_count === 1 ? 'person' : 'people'}`
                : ''}
            </p>
          </div>
          <p class="text-sm whitespace-nowrap">
            <span class={announcement.status === 'incomplete' ? 'font-medium text-status-caution-ink' : ''}
              >{STATUS[announcement.status]}</span
            >
            <span class="text-ink-muted"
              >{` · ${formatDate(announcement.sent_at ?? announcement.created_at, { year: true })}`}</span
            >
          </p>
        </li>
      {/each}
    </ul>
  {:else}
    <p class="rounded-lg border border-dashed border-line p-6 text-center text-sm text-ink-muted">
      No announcements yet.
    </p>
  {/if}
</div>
