<script lang="ts">
  import { Form, Link } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import TextField from '@/lib/components/TextField.svelte'
  import { usersConfirmations, usersSessions } from '@/routes'

  let { email = '' }: { email?: string } = $props()
</script>

<svelte:head><title>Resend confirmation · WISP</title></svelte:head>

<div>
  <h1 class="text-xl font-semibold">Resend confirmation email</h1>
  <p class="mt-1 text-sm text-ink-muted">
    You can also sign in with a one-time link from the sign-in page; using it confirms your email.
  </p>
</div>

<Form action={usersConfirmations.create()} class="space-y-4">
  {#snippet children({ errors, processing })}
    <TextField label="Email" name="user[email]" type="email" autocomplete="email" required value={email} error={errors.email} />
    <Button type="submit" class="w-full" disabled={processing}>Resend confirmation</Button>
  {/snippet}
</Form>

<p class="border-t border-line pt-4 text-center text-sm">
  <Link href={usersSessions.new()} class="text-brand-600 hover:underline">Back to sign in</Link>
</p>
