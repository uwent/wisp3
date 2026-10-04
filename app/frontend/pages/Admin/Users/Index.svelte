<script lang="ts">
  import { Link, page, router } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import DataTable from '@/lib/components/DataTable.svelte'
  import Dialog from '@/lib/components/Dialog.svelte'
  import { formatDate, formatTimestamp } from '@/lib/dates'
  import type { Column, SortDirection } from '@/lib/table'
  import { adminUsers } from '@/routes'
  import type { AdminUser } from '@/types/serializers'

  let { users }: { users: AdminUser[] } = $props()

  const me = $derived(page.props.auth.user?.id)
  let sort = $state<{ key: string; direction: SortDirection } | null>({ key: 'created', direction: 'desc' })
  // The unconfirmed account the dialog asks about; it stays set while the dialog closes
  let deleting = $state<AdminUser | null>(null)
  let dialogOpen = $state(false)
  let processing = $state(false)

  const columns: Column<AdminUser>[] = [
    { key: 'id', label: 'ID', value: (u) => u.id, align: 'right', searchable: true },
    { key: 'email', label: 'Email', value: (u) => u.email, searchable: true },
    { key: 'name', label: 'Name', value: (u) => (u.display_name === u.email ? null : u.display_name), searchable: true },
    { key: 'created', label: 'Created', value: (u) => u.created_at, text: (u) => formatDate(u.created_at, { year: true }), firstDirection: 'desc' },
    { key: 'confirmed', label: 'Confirmed', value: (u) => u.confirmed, text: (u) => (u.confirmed ? 'Yes' : 'No'), align: 'center', firstDirection: 'desc' },
    { key: 'signed_in', label: 'Last signed in', value: (u) => u.current_sign_in_at, text: (u) => formatDate(u.current_sign_in_at, { year: true }), firstDirection: 'desc' },
    { key: 'farms', label: 'Farms', value: (u) => u.farms_count, align: 'right', firstDirection: 'desc' },
    { key: 'pivots', label: 'Pivots', value: (u) => u.pivots_count, align: 'right', firstDirection: 'desc' },
    { key: 'fields', label: 'Fields', value: (u) => u.fields_count, align: 'right', firstDirection: 'desc' },
    { key: 'actions', label: '', value: () => null, sortable: false, align: 'right' },
  ]

  const unconfirmed = $derived(users.filter((u) => !u.confirmed).length)

  function confirmDelete(user: AdminUser) {
    deleting = user
    dialogOpen = true
  }

  function destroy() {
    if (!deleting) return
    router.delete(adminUsers.destroy(deleting.id).url, {
      preserveScroll: true,
      onStart: () => (processing = true),
      onFinish: () => {
        processing = false
        dialogOpen = false
      },
    })
  }
</script>

<svelte:head><title>Users · WISP</title></svelte:head>

<div class="space-y-4">
  <div>
    <h1 class="text-2xl font-semibold">Users</h1>
    <p class="text-sm text-ink-muted">
      {users.length} {users.length === 1 ? 'account' : 'accounts'}, {unconfirmed} unconfirmed. Open an account to see its details and farm setup. Farm, pivot and
      field counts are over every group the user belongs to. Unconfirmed accounts can be deleted here.
    </p>
  </div>

  <DataTable rows={users} {columns} rowKey={(u) => u.id} label="Users" searchPlaceholder="Search ID, email or name" bind:sort>
    {#snippet cell(user, column)}
      {#if column.key === 'email'}
        <Link href={adminUsers.show(user.id)} class="text-brand-600 hover:underline">{user.email}</Link>
        {#if user.id === me}<span class="text-xs text-ink-muted">(you)</span>{/if}
        {#if user.admin}<span class="ml-1 rounded-full bg-brand-50 px-2 py-0.5 text-xs text-brand-700">admin</span>{/if}
      {:else if column.key === 'confirmed'}
        <span class={user.confirmed ? '' : 'text-status-caution font-medium'}>{user.confirmed ? 'Yes' : 'No'}</span>
      {:else if column.key === 'signed_in'}
        <span class="whitespace-nowrap" title={formatTimestamp(user.current_sign_in_at)}>{formatDate(user.current_sign_in_at, { year: true })}</span>
      {:else if column.key === 'created'}
        <span class="whitespace-nowrap" title={formatTimestamp(user.created_at)}>{formatDate(user.created_at, { year: true })}</span>
      {:else if column.key === 'actions'}
        {#if !user.confirmed && !user.admin && user.id !== me}
          <Button variant="danger-ghost" class="!px-2 !py-1" onclick={() => confirmDelete(user)}>Delete</Button>
        {:else}
          <Link href={adminUsers.show(user.id)} class="px-2 text-sm text-brand-600 hover:underline">View</Link>
        {/if}
      {:else}
        <span class="tabular-nums">{column.value(user) ?? ''}</span>
      {/if}
    {/snippet}
  </DataTable>
</div>

<Dialog
  bind:open={dialogOpen}
  title="Delete {deleting?.email}?"
  description="The unconfirmed account is deleted, with any farms only it can reach. This can't be undone."
>
  <div class="flex justify-end gap-2">
    <Button variant="secondary" onclick={() => (dialogOpen = false)}>Cancel</Button>
    <Button variant="danger" disabled={processing} onclick={destroy}>Delete account</Button>
  </div>
</Dialog>
