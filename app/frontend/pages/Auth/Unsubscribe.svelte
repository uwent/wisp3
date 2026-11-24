<script lang="ts">
  import { Form, Link } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import { announcementUnsubscribes, digestUnsubscribes, settings } from '@/routes'

  // The daily email's unsubscribe link, or announcements' (each its own setting)
  let { kind, token, valid, done }: { kind: 'digest' | 'announcements'; token: string; valid: boolean; done: boolean } =
    $props()

  const copy = $derived(
    kind === 'digest'
      ? {
          title: 'Daily email',
          name: 'the daily email',
          ask: 'Stop the daily email?',
          what: 'WISP will stop sending you the morning summary of your fields.',
          action: digestUnsubscribes.create({ query: { token } }),
        }
      : {
          title: 'Announcements',
          name: 'announcements',
          ask: 'Stop announcements from WISP?',
          what: "WISP will stop sending you news about the program, such as new features and training sessions. The daily email isn't affected.",
          action: announcementUnsubscribes.create({ query: { token } }),
        },
  )
</script>

<svelte:head><title>{copy.title} · WISP</title></svelte:head>

{#if !valid}
  <div>
    <h1 class="text-xl font-semibold">This link doesn't work</h1>
    <p class="mt-1 text-sm text-ink-muted">
      This link may be from an older email. Sign in to WISP and turn {copy.name} off in your settings.
    </p>
  </div>
  <Link href={settings.show()} class="block text-center font-medium text-brand-600 hover:underline">
    Go to settings
  </Link>
{:else if done}
  <div>
    <h1 class="text-xl font-semibold">You're unsubscribed</h1>
    <p class="mt-1 text-sm text-ink-muted">
      WISP won't send you {copy.name}. You can turn {kind === 'digest' ? 'it' : 'them'} back on in your settings.
    </p>
  </div>
  <Link href={settings.show()} class="block text-center font-medium text-brand-600 hover:underline">
    Go to settings
  </Link>
{:else}
  <div>
    <h1 class="text-xl font-semibold">{copy.ask}</h1>
    <p class="mt-1 text-sm text-ink-muted">
      {copy.what} You can turn {kind === 'digest' ? 'it' : 'them'} back on in your settings.
    </p>
  </div>
  <Form action={copy.action}>
    {#snippet children({ processing })}
      <Button type="submit" class="w-full" disabled={processing}>Unsubscribe</Button>
    {/snippet}
  </Form>
{/if}
