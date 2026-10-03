<script lang="ts">
  import { Form, Link } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import TextField from '@/lib/components/TextField.svelte'
  import { magicLinks, usersConfirmations, usersPasswords, usersRegistrations, usersSessions } from '@/routes'

  let { email = '' }: { email?: string } = $props()

  let mode = $state<'password' | 'link'>('password')
  // Shared between both forms so switching modes keeps what was typed (seeded once from the prop)
  // svelte-ignore state_referenced_locally
  let emailValue = $state(email)
</script>

<svelte:head><title>Sign in · WISP</title></svelte:head>

<h1 class="text-xl font-semibold">Sign in</h1>

<div class="grid grid-cols-2 rounded-md border border-line p-1 text-sm" role="tablist">
  {#each [['password', 'Password'], ['link', 'Email me a code']] as [value, label] (value)}
    <button
      type="button"
      role="tab"
      aria-selected={mode === value}
      class="rounded px-3 py-1.5 font-medium {mode === value ? 'bg-brand-50 text-brand-700' : 'text-ink-muted'}"
      onclick={() => (mode = value as typeof mode)}>{label}</button
    >
  {/each}
</div>

{#if mode === 'password'}
  <Form action={usersSessions.create()} class="space-y-4">
    {#snippet children({ processing })}
      <TextField label="Email" name="user[email]" type="email" autocomplete="email" required bind:value={emailValue} />
      <TextField label="Password" name="user[password]" type="password" autocomplete="current-password" required />
      <label class="flex items-center gap-2 text-sm">
        <input type="checkbox" name="user[remember_me]" value="1" class="rounded" />
        Keep me signed in on this device
      </label>
      <Button type="submit" class="w-full" disabled={processing}>Sign in</Button>
    {/snippet}
  </Form>
  <p class="text-center text-sm">
    <Link href={usersPasswords.new()} class="text-brand-600 hover:underline">Forgot your password?</Link>
  </p>
{:else}
  <Form action={magicLinks.create()} class="space-y-4">
    {#snippet children({ errors, processing })}
      <TextField
        label="Email"
        name="email"
        type="email"
        autocomplete="email"
        required
        bind:value={emailValue}
        error={errors.email}
        hint="We'll email you a 6-digit code and a one-click sign-in link. No password needed."
      />
      <Button type="submit" class="w-full" disabled={processing}>Email me a code</Button>
    {/snippet}
  </Form>
{/if}

<div class="space-y-1 border-t border-line pt-4 text-center text-sm text-ink-muted">
  <p>
    New to WISP?
    <Link href={usersRegistrations.new()} class="font-medium text-brand-600 hover:underline">Create an account</Link>
  </p>
  <p>
    <Link href={usersConfirmations.new()} class="hover:underline">Didn't get your confirmation email?</Link>
  </p>
</div>
