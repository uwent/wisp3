<script lang="ts">
  import { Form, page } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import TextField from '@/lib/components/TextField.svelte'
  import { confirmUnsavedChanges } from '@/lib/unsaved.svelte'
  import { settings, usersRegistrations } from '@/routes'

  let {
    unit_systems,
    pending_email,
    announcements,
  }: { unit_systems: string[]; pending_email: string | null; announcements: boolean } = $props()

  const user = $derived(page.props.auth.user!)
  // An admin signed in as this user for support can't change their email or password, or delete them
  const impersonating = $derived(!!page.props.auth.impersonator)

  const unitLabels: Record<string, { name: string; detail: string }> = {
    imperial: { name: 'US units', detail: 'inches, °F, acres, gpm' },
    metric: { name: 'Metric', detail: 'millimeters, °C, hectares, L/s' },
  }

  // Typed values not yet saved, per form; cleared by its save. The confirm lists the profile form's
  // changes only, so a typed password is never shown in it
  let profileDirty = $state(false)
  let accountDirty = $state(false)
  confirmUnsavedChanges(
    () => profileDirty || accountDirty,
    () => document.getElementById('profile-form'),
  )

  // Returning false from onBefore cancels the request
  const confirmDelete = () =>
    confirm("Delete your account? This can't be undone. Farm data that only you can access will be deleted with it.")
</script>

<svelte:head><title>Settings · WISP</title></svelte:head>

<h1 class="text-2xl font-semibold">Settings</h1>

<section class="space-y-4 rounded-lg border border-line bg-surface-raised p-6">
  <h2 class="text-lg font-medium">Profile and units</h2>
  <Form
    id="profile-form"
    action={settings.update()}
    class="max-w-xl space-y-4"
    options={{ preserveScroll: true }}
    oninput={() => (profileDirty = true)}
    onchange={() => (profileDirty = true)}
    onSuccess={() => (profileDirty = false)}
  >
    {#snippet children({ errors, processing })}
      <div class="grid gap-4 sm:grid-cols-2">
        <TextField
          label="First name"
          name="user[first_name]"
          value={user.first_name ?? ''}
          error={errors.first_name}
          optional
        />
        <TextField
          label="Last name"
          name="user[last_name]"
          value={user.last_name ?? ''}
          error={errors.last_name}
          optional
        />
      </div>
      <fieldset class="space-y-2">
        <legend class="text-sm font-medium">Units</legend>
        <p class="text-sm text-ink-muted">
          Choose how amounts are shown and entered. WISP keeps its records in inches and converts them for you.
        </p>
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
      <fieldset class="space-y-2">
        <legend class="text-sm font-medium">Email</legend>
        <input type="hidden" name="user[announcements]" value="0" />
        <label class="flex items-start gap-3 text-sm">
          <input type="checkbox" name="user[announcements]" value="1" checked={announcements} class="mt-0.5 rounded" />
          <span
            ><span class="font-medium">Announcements from WISP</span>
            <span class="block text-ink-muted"
              >News about the program, such as new features and training sessions. The daily email is set on the Alerts
              page.</span
            ></span
          >
        </label>
      </fieldset>
      <Button type="submit" disabled={processing}>Save</Button>
    {/snippet}
  </Form>
</section>

{#if impersonating}
  <section class="space-y-2 rounded-lg border border-line bg-surface-raised p-6">
    <h2 class="text-lg font-medium">Email, password and account</h2>
    <p class="text-sm text-ink-muted">
      Changing the email or password and deleting the account are turned off while you're signed in as someone else.
    </p>
  </section>
{:else}
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
      oninput={() => (accountDirty = true)}
      onchange={() => (accountDirty = true)}
      onSuccess={() => (accountDirty = false)}
    >
      {#snippet children({ errors, processing })}
        <TextField
          label="Email"
          name="user[email]"
          type="email"
          autocomplete="email"
          value={user.email}
          error={errors.email}
          required
        />
        <div class="grid gap-4 sm:grid-cols-2">
          <TextField
            label="New password"
            name="user[password]"
            type="password"
            autocomplete="new-password"
            hint="Leave blank to keep your current password"
            error={errors.password}
            optional
          />
          <TextField
            label="Confirm new password"
            name="user[password_confirmation]"
            type="password"
            autocomplete="new-password"
            error={errors.password_confirmation}
            optional
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
      This permanently deletes your account. Operations you share with other people stay with them.
    </p>
    <Form action={usersRegistrations.destroy()} onBefore={confirmDelete}>
      {#snippet children({ processing })}
        <Button type="submit" variant="danger" disabled={processing}>Delete my account</Button>
      {/snippet}
    </Form>
  </section>
{/if}
