<script lang="ts">
  import { Link } from '@inertiajs/svelte'

  import EmailPreview, { type DigestPreview } from '@/lib/components/EmailPreview.svelte'
  import { adminUsers } from '@/routes'

  let { user, preview }: { user: { id: number; email: string }; preview: DigestPreview } = $props()
</script>

<svelte:head><title>Daily email · {user.email} · WISP</title></svelte:head>

<div class="space-y-4">
  <div>
    <Link href={adminUsers.show(user.id)} class="text-sm text-brand-600 hover:underline">← {user.email}</Link>
    <h1 class="text-2xl font-semibold">Today's daily email</h1>
    <p class="text-sm text-ink-muted">What the 6 am digest would send {user.email} with today's data. Nothing is sent from here.</p>
  </div>

  <EmailPreview {preview} />
</div>
