<script lang="ts">
  import { Form, Link } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import TextField from '@/lib/components/TextField.svelte'
  import { usersPasswords } from '@/routes'

  let { reset_password_token, minimum_password_length }: { reset_password_token: string; minimum_password_length: number } =
    $props()
</script>

<svelte:head><title>Choose a new password · WISP</title></svelte:head>

<h1 class="text-xl font-semibold">Choose a new password</h1>

<Form action={usersPasswords.update()} class="space-y-4" resetOnError>
  {#snippet children({ errors, processing })}
    {#if errors.reset_password_token}
      <p class="rounded-md bg-status-irrigate/10 px-3 py-2 text-sm" role="alert">
        This reset link is invalid or has expired.
        <Link href={usersPasswords.new()} class="font-medium text-brand-600 hover:underline">Request a new one</Link>.
      </p>
    {/if}
    <input type="hidden" name="user[reset_password_token]" value={reset_password_token} />
    <TextField
      label="New password"
      name="user[password]"
      type="password"
      autocomplete="new-password"
      required
      minlength={minimum_password_length}
      hint="At least {minimum_password_length} characters"
      error={errors.password}
    />
    <TextField
      label="Confirm new password"
      name="user[password_confirmation]"
      type="password"
      autocomplete="new-password"
      required
      error={errors.password_confirmation}
    />
    <Button type="submit" class="w-full" disabled={processing}>Save password and sign in</Button>
  {/snippet}
</Form>
