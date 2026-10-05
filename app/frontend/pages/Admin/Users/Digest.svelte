<script lang="ts">
  import { Link } from '@inertiajs/svelte'

  import { adminUsers } from '@/routes'

  let {
    user,
    skip_reason,
    subject,
    html,
  }: { user: { id: number; email: string }; skip_reason: string | null; subject: string | null; html: string | null } =
    $props()
</script>

<svelte:head><title>Daily email · {user.email} · WISP</title></svelte:head>

<div class="space-y-4">
  <div>
    <Link href={adminUsers.show(user.id)} class="text-sm text-brand-600 hover:underline">← {user.email}</Link>
    <h1 class="text-2xl font-semibold">Today's daily email</h1>
    <p class="text-sm text-ink-muted">What the 6 am digest would send {user.email} with today's data. Nothing is sent from here.</p>
  </div>

  {#if skip_reason}
    <p class="rounded-md bg-status-caution/15 px-3 py-2 text-sm">Nothing would be sent today: {skip_reason}</p>
  {/if}

  {#if html}
    <p class="text-sm"><span class="text-ink-muted">Subject:</span> <span class="font-medium">{subject}</span></p>
    <!-- The email as a mail client shows it: its own document, light background, no scripts -->
    <iframe
      title="Daily email preview"
      srcdoc={html}
      sandbox="allow-popups"
      class="h-[80vh] w-full rounded-lg border border-line bg-white"
    ></iframe>
  {/if}
</div>
