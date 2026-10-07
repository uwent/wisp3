<script lang="ts">
  import { Link, page, router } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import Dialog from '@/lib/components/Dialog.svelte'
  import { formatDate, formatTimestamp } from '@/lib/dates'
  import { units as unitsFor } from '@/lib/units'
  import { adminUsers } from '@/routes'
  import type { AdminGroup, AdminUserDetail, Field } from '@/types/serializers'

  let { user, groups, deletable }: { user: AdminUserDetail; groups: AdminGroup[]; deletable: boolean } = $props()

  const units = $derived(unitsFor(page.props.auth.user?.unit_system))
  const isMe = $derived(page.props.auth.user?.id === user.id)

  // Deleting the account deletes the groups only it belongs to, with their farms
  const deletedGroups = $derived(groups.filter((group) => group.members.length === 1))
  const counts = (list: AdminGroup[]) => {
    const farms = list.flatMap((group) => group.farms)
    const pivots = farms.flatMap((farm) => farm.pivots)
    return { farms: farms.length, pivots: pivots.length, fields: pivots.flatMap((pivot) => pivot.fields).length }
  }
  const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? '' : 's'}`
  const summary = (list: AdminGroup[]) => {
    const { farms, pivots, fields } = counts(list)
    return `${plural(farms, 'farm')}, ${plural(pivots, 'pivot')}, ${plural(fields, 'field')}`
  }

  const digestFrequencies = { never: 'Never', daily: 'Daily during season', needed: 'Only when irrigation is needed' }

  const attributes = $derived<[string, string][]>([
    ['Name', user.display_name === user.email ? '—' : user.display_name],
    ['Email', user.email],
    ...(user.unconfirmed_email ? [['Email change pending', user.unconfirmed_email] as [string, string]] : []),
    ['Units', user.unit_system === 'metric' ? 'Metric' : 'US (imperial)'],
    [
      'Daily email',
      `${digestFrequencies[user.digest_frequency]}${user.digest_sent_on ? `, last sent ${formatDate(user.digest_sent_on, { year: true })}` : ''}`,
    ],
    ['WISP admin', user.admin ? 'Yes' : 'No'],
    ['Created', formatTimestamp(user.created_at)],
    ['Last updated', formatTimestamp(user.updated_at)],
    ['Confirmed', user.confirmed_at ? formatTimestamp(user.confirmed_at) : 'Not confirmed'],
    ['Confirmation email sent', formatTimestamp(user.confirmation_sent_at)],
    ['Sign-ins', String(user.sign_in_count)],
    ['Last signed in', withIp(user.current_sign_in_at, user.current_sign_in_ip)],
    ['Signed in before that', withIp(user.last_sign_in_at, user.last_sign_in_ip)],
    ['Password reset requested', formatTimestamp(user.reset_password_sent_at)],
    ['“Remember me” set', formatTimestamp(user.remember_created_at)],
  ])

  function withIp(at: string | null, ip: string | null) {
    return at ? `${formatTimestamp(at)}${ip ? ` from ${ip}` : ''}` : '—'
  }

  /** The field's latest planting, as "Corn 2026" */
  function crop(field: Field) {
    const latest = field.plantings.at(-1)
    return latest
      ? `${latest.plant_name}${latest.variety ? ` (${latest.variety})` : ''} ${latest.year}`
      : 'no plantings'
  }

  let dialogOpen = $state(false)
  let processing = $state(false)

  function destroy() {
    router.delete(adminUsers.destroy(user.id).url, {
      onStart: () => (processing = true),
      onFinish: () => {
        processing = false
        dialogOpen = false
      },
    })
  }
</script>

<svelte:head><title>{user.email} · Users · WISP</title></svelte:head>

<div class="space-y-6">
  <div>
    <Link href={adminUsers.index()} class="text-sm text-brand-600 hover:underline">← Users</Link>
    <h1 class="text-2xl font-semibold">
      User {user.id}: {user.email}
      {#if isMe}<span class="text-base font-normal text-ink-muted">(you)</span>{/if}
    </h1>
  </div>

  <section class="space-y-2">
    <div class="flex items-baseline justify-between gap-3">
      <h2 class="font-medium">Account</h2>
      <Link href={adminUsers.digest(user.id)} class="text-sm text-brand-600 hover:underline"
        >Preview today's daily email</Link
      >
    </div>
    <dl class="grid gap-x-6 rounded-lg border border-line bg-surface-raised p-4 text-sm sm:grid-cols-[max-content_1fr]">
      {#each attributes as [label, value] (label)}
        <dt class="pt-2 text-ink-muted first:pt-0 sm:py-0.5">{label}</dt>
        <dd class="sm:py-0.5">{value}</dd>
      {/each}
    </dl>
  </section>

  <section class="space-y-3">
    <h2 class="font-medium">Farm setup</h2>
    {#each groups as group (group.id)}
      <div class="space-y-3 rounded-lg border border-line bg-surface-raised p-4">
        <div>
          <h3 class="font-medium">{group.name}</h3>
          <p class="text-xs text-ink-muted">
            Group {group.id} · {summary([group])} · rain from {group.use_model_precip
              ? 'the weather model'
              : 'entries only'}
          </p>
          <p class="mt-1 text-sm">
            Members:
            {#each group.members as member, i (member.id)}
              <span>
                {#if member.id === user.id}{member.email}{:else}<Link
                    href={adminUsers.show(member.id)}
                    class="text-brand-600 hover:underline">{member.email}</Link
                  >{/if}
                {#if member.owner}<span class="text-ink-muted">(owner)</span>{/if}{i < group.members.length - 1
                  ? ','
                  : ''}
              </span>
            {/each}
          </p>
        </div>
        {#if group.farms.length === 0}
          <p class="text-sm text-ink-muted">No farms set up.</p>
        {:else}
          <ul class="space-y-3 text-sm">
            {#each group.farms as farm (farm.id)}
              <li>
                <div class="font-medium">
                  Farm: {farm.name} <span class="font-normal text-ink-muted">(#{farm.id})</span>
                </div>
                {#if farm.pivots.length === 0}
                  <p class="ml-4 text-ink-muted">No pivots.</p>
                {:else}
                  <ul class="ml-4 space-y-2 border-l border-line pl-3">
                    {#each farm.pivots as pivot (pivot.id)}
                      <li>
                        <div>
                          Pivot: {pivot.name}
                          <a
                            class="font-mono text-xs text-brand-600 hover:underline"
                            href="https://www.openstreetmap.org/?mlat={pivot.latitude}&mlon={pivot.longitude}#map=15/{pivot.latitude}/{pivot.longitude}"
                            target="_blank"
                            rel="noopener noreferrer">{pivot.latitude.toFixed(4)}, {pivot.longitude.toFixed(4)}</a
                          >
                          <span class="text-xs text-ink-muted">(#{pivot.id})</span>
                        </div>
                        {#if pivot.fields.length === 0}
                          <p class="ml-4 text-ink-muted">No fields.</p>
                        {:else}
                          <ul class="ml-4 border-l border-line pl-3">
                            {#each pivot.fields as field (field.id)}
                              <li>
                                Field: {field.name} · {crop(field)}
                                <span class="text-xs text-ink-muted">
                                  · {field.soil_type_name}{field.area_acres !== null
                                    ? ` · ${units.format('area', field.area_acres)}`
                                    : ''}
                                  · {plural(field.plantings.length, 'planting')} (#{field.id})
                                </span>
                              </li>
                            {/each}
                          </ul>
                        {/if}
                      </li>
                    {/each}
                  </ul>
                {/if}
              </li>
            {/each}
          </ul>
        {/if}
      </div>
    {:else}
      <p class="text-sm text-ink-muted">Not in any group.</p>
    {/each}
  </section>

  <section class="space-y-2">
    <h2 class="font-medium">Actions</h2>
    {#if deletable}
      <Button variant="danger" onclick={() => (dialogOpen = true)}>Delete this account</Button>
    {:else}
      <p class="text-sm text-ink-muted">
        {isMe
          ? "You can't delete your own account here; use Settings."
          : "Another admin's account can't be deleted here."}
      </p>
    {/if}
  </section>
</div>

<Dialog bind:open={dialogOpen} title="Delete {user.email}?" description="This can't be undone.">
  <div class="space-y-4 text-sm">
    {#if deletedGroups.length}
      <p>
        These groups have no other members and are deleted with the account, including {summary(deletedGroups)} and every
        entry in them:
      </p>
      <ul class="list-disc pl-5">
        {#each deletedGroups as group (group.id)}<li>{group.name}</li>{/each}
      </ul>
      {#if deletedGroups.length < groups.length}<p class="text-ink-muted">
          Groups shared with other members are kept.
        </p>{/if}
    {:else}
      <p>Only the account is deleted: its groups have other members and are kept.</p>
    {/if}
    <div class="flex justify-end gap-2">
      <Button variant="secondary" onclick={() => (dialogOpen = false)}>Cancel</Button>
      <Button variant="danger" disabled={processing} onclick={destroy}>Delete account</Button>
    </div>
  </div>
</Dialog>
