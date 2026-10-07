<script lang="ts">
  import { Form, page } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import TextField from '@/lib/components/TextField.svelte'
  import { settings, usersRegistrations } from '@/routes'

  let { unit_systems, pending_email }: { unit_systems: string[]; pending_email: string | null } = $props()

  const user = $derived(page.props.auth.user!)

  const unitLabels: Record<string, { name: string; detail: string }> = {
    imperial: { name: 'US units', detail: 'inches, °F, acres, gpm' },
    metric: { name: 'Metric', detail: 'millimeters, °C, hectares, L/s' },
  }

  // Returning false from onBefore cancels the request
  const confirmDelete = () =>
    confirm('Delete your account? This permanently deletes your account and any farm data only you can access.')
</script>

<svelte:head><title>Settings · WISP</title></svelte:head>

<h1 class="text-2xl font-semibold">Settings</h1>

<section class="space-y-4 rounded-lg border border-line bg-surface-raised p-6">
  <h2 class="text-lg font-medium">Profile and units</h2>
  <Form action={settings.update()} class="max-w-xl space-y-4" options={{ preserveScroll: true }}>
    {#snippet children({ errors, processing })}
      <div class="grid gap-4 sm:grid-cols-2">
        <TextField label="First name" name="user[first_name]" value={user.first_name ?? ''} error={errors.first_name} />
        <TextField label="Last name" name="user[last_name]" value={user.last_name ?? ''} error={errors.last_name} />
      </div>
      <fieldset class="space-y-2">
        <legend class="text-sm font-medium">Units</legend>
        <p class="text-sm text-ink-muted">How values are shown and entered. WISP stores everything in inches.</p>
        {#each unit_systems as system (system)}
          <label class="flex items-center gap-3 text-sm">
            <input type="radio" name="user[unit_system]" value={system} checked={user.unit_system === system} />
            <span
              ><span class="font-medium">{unitLabels[system]?.name ?? system}</span>
              <span class="text-ink-muted">({unitLabels[system]?.detail})</span></span
            >
          </label>
        {/each}
      </fieldset>
      <Button type="submit" disabled={processing}>Save</Button>
    {/snippet}
  </Form>
</section>

<section class="space-y-4 rounded-lg border border-line bg-surface-raised p-6">
  <div>
    <h2 class="text-lg font-medium">Email and password</h2>
    <p class="text-sm text-ink-muted">Enter your current password to change either one.</p>
  </div>
  {#if pending_email}
    <p class="rounded-md bg-status-caution/15 px-3 py-2 text-sm">
      Waiting for you to confirm <strong>{pending_email}</strong>. Check that inbox for the confirmation link.
    </p>
  {/if}
  <Form
    action={usersRegistrations.update()}
    class="max-w-xl space-y-4"
    options={{ preserveScroll: true }}
    resetOnSuccess={['user[password]', 'user[password_confirmation]', 'user[current_password]']}
    resetOnError={['user[password]', 'user[password_confirmation]', 'user[current_password]']}
  >
    {#snippet children({ errors, processing })}
      <TextField
        label="Email"
        name="user[email]"
        type="email"
        autocomplete="email"
        value={user.email}
        error={errors.email}
      />
      <div class="grid gap-4 sm:grid-cols-2">
        <TextField
          label="New password"
          name="user[password]"
          type="password"
          autocomplete="new-password"
          hint="Leave blank to keep your current password"
          error={errors.password}
        />
        <TextField
          label="Confirm new password"
          name="user[password_confirmation]"
          type="password"
          autocomplete="new-password"
          error={errors.password_confirmation}
        />
      </div>
      <TextField
        label="Current password"
        name="user[current_password]"
        type="password"
        autocomplete="current-password"
        required
        error={errors.current_password}
      />
      <Button type="submit" disabled={processing}>Update email or password</Button>
    {/snippet}
  </Form>
</section>

<section class="space-y-3 rounded-lg border border-status-irrigate/40 bg-surface-raised p-6">
  <h2 class="text-lg font-medium">Delete account</h2>
  <p class="text-sm text-ink-muted">
    Permanently deletes your account. Farm operations shared with other people stay with them.
  </p>
  <Form action={usersRegistrations.destroy()} onBefore={confirmDelete}>
    {#snippet children({ processing })}
      <Button type="submit" variant="danger" disabled={processing}>Delete my account</Button>
    {/snippet}
  </Form>
</section>
