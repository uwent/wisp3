<script lang="ts">
  import { Form, Link } from '@inertiajs/svelte'

  import { track } from '@/lib/analytics'
  import Button from '@/lib/components/Button.svelte'
  import TextField from '@/lib/components/TextField.svelte'
  import { usersRegistrations, usersSessions } from '@/routes'

  let { minimum_password_length, form_token }: { minimum_password_length: number; form_token: string } = $props()
</script>

<svelte:head><title>Create an account · WISP</title></svelte:head>

<div>
  <h1 class="text-xl font-semibold">Create an account</h1>
  <p class="mt-1 text-sm text-ink-muted">
    This is a new version of WISP. Accounts from the previous version don't carry over, so you'll need to create a new
    one.
  </p>
</div>

<Form
  action={usersRegistrations.create()}
  class="space-y-4"
  resetOnError={['user[password]', 'user[password_confirmation]']}
  onSuccess={() => track('sign_up')}
>
  {#snippet children({ errors, processing })}
    <!-- Bot checks (SignUpGuard): when the page was shown, and a field only bots fill in -->
    <input type="hidden" name="form_token" value={form_token} />
    <div class="absolute left-[-10000px] h-px w-px overflow-hidden" aria-hidden="true">
      <label>Website <input type="text" name="website" tabindex="-1" autocomplete="off" /></label>
    </div>
    <div class="grid gap-4 sm:grid-cols-2">
      <TextField
        label="First name"
        name="user[first_name]"
        autocomplete="given-name"
        error={errors.first_name}
        optional
      />
      <TextField
        label="Last name"
        name="user[last_name]"
        autocomplete="family-name"
        error={errors.last_name}
        optional
      />
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
