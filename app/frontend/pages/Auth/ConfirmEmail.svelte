<script lang="ts">
  import { Form, Link } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import { usersConfirmations, usersSessions } from '@/routes'

  let { token, status }: { token: string; status: 'pending' | 'confirmed' | 'invalid' } = $props()
</script>

<svelte:head><title>Confirm email · WISP</title></svelte:head>

{#if status === 'pending'}
  <div>
    <h1 class="text-xl font-semibold">Confirm your email</h1>
    <p class="mt-1 text-sm text-ink-muted">One click and you can sign in to WISP.</p>
  </div>
  <Form action={usersConfirmations.confirm()}>
    {#snippet children({ processing })}
      <input type="hidden" name="confirmation_token" value={token} />
      <Button type="submit" class="w-full" disabled={processing}>Confirm my email</Button>
    {/snippet}
  </Form>
{:else if status === 'confirmed'}
  <div>
    <h1 class="text-xl font-semibold">Email already confirmed</h1>
    <p class="mt-1 text-sm text-ink-muted">This address is confirmed, so you can sign in.</p>
  </div>
  <Link href={usersSessions.new()} class="block text-center font-medium text-brand-600 hover:underline">
    Sign in
  </Link>
{:else}
  <div>
    <h1 class="text-xl font-semibold">This link doesn't work</h1>
    <p class="mt-1 text-sm text-ink-muted">
      It may be from an older email. Request a new confirmation link, or sign in if you've already confirmed.
    </p>
  </div>
  <Link href={usersConfirmations.new()} class="block text-center font-medium text-brand-600 hover:underline">
    Send a new link
  </Link>
{/if}
