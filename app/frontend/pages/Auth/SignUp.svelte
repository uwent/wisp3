<script lang="ts">
  import { Form, Link } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import TextField from '@/lib/components/TextField.svelte'
  import { usersRegistrations, usersSessions } from '@/routes'

  let { minimum_password_length }: { minimum_password_length: number } = $props()
</script>

<svelte:head><title>Create an account · WISP</title></svelte:head>

<div>
  <h1 class="text-xl font-semibold">Create an account</h1>
  <p class="mt-1 text-sm text-ink-muted">
    WISP 3 is a fresh start: accounts from the previous version of WISP don't carry over.
  </p>
</div>

<Form action={usersRegistrations.create()} class="space-y-4" resetOnError={['user[password]', 'user[password_confirmation]']}>
  {#snippet children({ errors, processing })}
    <div class="grid gap-4 sm:grid-cols-2">
      <TextField label="First name" name="user[first_name]" autocomplete="given-name" error={errors.first_name} />
      <TextField label="Last name" name="user[last_name]" autocomplete="family-name" error={errors.last_name} />
    </div>
    <TextField label="Email" name="user[email]" type="email" autocomplete="email" required error={errors.email} />
    <TextField
      label="Password"
      name="user[password]"
      type="password"
      autocomplete="new-password"
      required
      minlength={minimum_password_length}
      hint="At least {minimum_password_length} characters"
      error={errors.password}
    />
    <TextField
      label="Confirm password"
      name="user[password_confirmation]"
      type="password"
      autocomplete="new-password"
      required
      error={errors.password_confirmation}
    />
    <Button type="submit" class="w-full" disabled={processing}>Create account</Button>
  {/snippet}
</Form>

<p class="border-t border-line pt-4 text-center text-sm text-ink-muted">
  Already have an account?
  <Link href={usersSessions.new()} class="font-medium text-brand-600 hover:underline">Sign in</Link>
</p>
