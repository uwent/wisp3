<script lang="ts">
  import { Form, Link } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import { magicLinks, usersSessions } from '@/routes'

  let { token, valid, ttl_minutes }: { token: string; valid: boolean; ttl_minutes: number } = $props()
</script>

<svelte:head><title>Sign in · WISP</title></svelte:head>

{#if valid}
  <div>
    <h1 class="text-xl font-semibold">Sign in to WISP</h1>
    <p class="mt-1 text-sm text-ink-muted">This link signs you in once.</p>
  </div>
  <Form action={magicLinks.redeem({ token })}>
    {#snippet children({ processing })}
      <Button type="submit" class="w-full" disabled={processing}>Sign in</Button>
    {/snippet}
  </Form>
{:else}
  <div>
    <h1 class="text-xl font-semibold">This link has expired</h1>
    <p class="mt-1 text-sm text-ink-muted">
      Sign-in links work once and expire after {ttl_minutes} minutes.
    </p>
  </div>
  <Link href={usersSessions.new()} class="block text-center font-medium text-brand-600 hover:underline">
    Request a new link
  </Link>
{/if}
