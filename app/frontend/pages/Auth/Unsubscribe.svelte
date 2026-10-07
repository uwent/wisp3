<script lang="ts">
  import { Form, Link } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import { digestUnsubscribes, settings } from '@/routes'

  let { token, valid, done }: { token: string; valid: boolean; done: boolean } = $props()
</script>

<svelte:head><title>Daily email · WISP</title></svelte:head>

{#if !valid}
  <div>
    <h1 class="text-xl font-semibold">This link doesn't work</h1>
    <p class="mt-1 text-sm text-ink-muted">Sign in and turn the daily email off in your settings.</p>
  </div>
  <Link href={settings.show()} class="block text-center font-medium text-brand-600 hover:underline">Go to settings</Link
  >
{:else if done}
  <div>
    <h1 class="text-xl font-semibold">You're unsubscribed</h1>
    <p class="mt-1 text-sm text-ink-muted">
      WISP won't send you the daily email. You can turn it back on in your settings.
    </p>
  </div>
  <Link href={settings.show()} class="block text-center font-medium text-brand-600 hover:underline">Go to settings</Link
  >
{:else}
  <div>
    <h1 class="text-xl font-semibold">Stop the daily email?</h1>
    <p class="mt-1 text-sm text-ink-muted">
      WISP will stop sending you the morning summary of your fields. You can turn it back on in your settings.
    </p>
  </div>
  <Form action={digestUnsubscribes.create({ token })}>
    {#snippet children({ processing })}
      <Button type="submit" class="w-full" disabled={processing}>Unsubscribe</Button>
    {/snippet}
  </Form>
{/if}
