<script lang="ts">
  import { Form, Link } from '@inertiajs/svelte'
  import { untrack } from 'svelte'

  import Button from '@/lib/components/Button.svelte'
  import TextField from '@/lib/components/TextField.svelte'
  import { magicLinks, usersSessions } from '@/routes'

  let { email, ttl_minutes, resend_in }: { email: string; ttl_minutes: number; resend_in: number } = $props()

  // Counts down to when another email may be requested (the server enforces the same wait)
  let now = $state(Date.now())
  const resendAt = $derived(untrack(() => now) + resend_in * 1000)
  const remaining = $derived(Math.max(0, Math.ceil((resendAt - now) / 1000)))
  $effect(() => {
    const timer = setInterval(() => (now = Date.now()), 1000)
    return () => clearInterval(timer)
  })
</script>

<svelte:head><title>Check your email · WISP</title></svelte:head>

<div>
  <h1 class="text-xl font-semibold">Check your email</h1>
  <p class="mt-1 text-sm text-ink-muted">
    If there's an account for <span class="font-medium text-ink">{email}</span>, we've sent it a 6-digit code and a
    sign-in link. Enter the code here, or open the link on the device where you read the email. Both work once and
    expire in {ttl_minutes} minutes.
  </p>
</div>

<Form action={magicLinks.verify()} class="space-y-4">
  {#snippet children({ errors, processing })}
    <TextField
      label="Sign-in code"
      name="code"
      inputmode="numeric"
      autocomplete="one-time-code"
      pattern="[0-9 ]*"
      maxlength={7}
      required
      autofocus
      class="text-center font-mono text-2xl tracking-[0.4em] sm:text-2xl"
      error={errors.code}
    />
    <Button type="submit" class="w-full" disabled={processing}>Sign in</Button>
  {/snippet}
</Form>

<Form action={magicLinks.create()}>
  {#snippet children({ processing })}
    <input type="hidden" name="email" value={email} />
    <Button type="submit" variant="secondary" class="w-full" disabled={processing || remaining > 0}>
      {remaining > 0 ? `Send a new code in ${remaining}s` : 'Send a new code'}
    </Button>
  {/snippet}
</Form>

<p class="text-center text-sm">
  <Link href={usersSessions.new({ query: { email } })} class="text-brand-600 hover:underline">
    Use a different email or a password
  </Link>
</p>
