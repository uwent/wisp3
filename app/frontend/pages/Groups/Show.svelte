<script lang="ts">
  import { Form, page, router } from '@inertiajs/svelte'

  import Button from '@/lib/components/Button.svelte'
  import Dialog from '@/lib/components/Dialog.svelte'
  import SelectField from '@/lib/components/SelectField.svelte'
  import TextField from '@/lib/components/TextField.svelte'
  import { formatDate } from '@/lib/dates'
  import { currentGroups, groups, memberships } from '@/routes'
  import type { Member } from '@/types/serializers'

  let {
    members,
    membership_id,
    counts,
    operations,
  }: {
    members: Member[]
    membership_id: number
    counts: { farms: number; pivots: number; fields: number }
    operations: { id: number; name: string; owner: boolean; members: number }[]
  } = $props()

  const group = $derived(page.props.auth.group!)
  const owner = $derived(page.props.auth.owner)
  const ownerCount = $derived(members.filter((member) => member.owner).length)

  const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? '' : 's'}`
  const setupSummary = $derived(
    `${plural(counts.farms, 'farm')}, ${plural(counts.pivots, 'pivot')} and ${plural(counts.fields, 'field')}`,
  )

  // Matches Membership#removal_error and #demotion_error, which the server checks
  const lastOwner = (member: Member) => member.owner && ownerCount === 1

  function setRole(member: Member, makeOwner: boolean) {
    router.patch(
      memberships.update(member.id).url,
      { membership: { owner: String(makeOwner) } },
      { preserveScroll: true },
    )
  }

  function remove(member: Member) {
    const you = member.id === membership_id
    const question = you
      ? `Leave ${group.name}? You'll lose access to its farms until an owner adds you again.`
      : `Remove ${member.name ?? member.email} from ${group.name}?`
    if (confirm(question)) router.delete(memberships.destroy(member.id).url, { preserveScroll: true })
  }

  function switchTo(id: number) {
    const { url, method } = currentGroups.update()
    router.visit(url, { method, data: { group_id: id } })
  }

  let deleteOpen = $state(false)
  let deleting = $state(false)
  function destroy() {
    router.delete(groups.destroy().url, {
      onStart: () => (deleting = true),
      onFinish: () => (deleting = false),
    })
  }
</script>

<svelte:head><title>{group.name} · WISP</title></svelte:head>

<div>
  <h1 class="text-2xl font-semibold">{group.name}</h1>
  <p class="text-sm text-ink-muted">
    Farm operation · {setupSummary} · you're {owner ? 'an owner' : 'a member'}
  </p>
</div>

<section class="space-y-4 rounded-lg border border-line bg-surface-raised p-6">
  <h2 class="text-lg font-medium">Settings</h2>
  {#if owner}
    <Form action={groups.update()} class="max-w-xl space-y-4" options={{ preserveScroll: true }}>
      {#snippet children({ errors, processing })}
        <TextField label="Operation name" name="group[name]" value={group.name} error={errors.name} />
        <fieldset class="space-y-2">
          <legend class="text-sm font-medium">Rainfall</legend>
          <label class="flex items-start gap-3 text-sm">
            <input
              type="radio"
              name="group[use_model_precip]"
              value="true"
              checked={group.use_model_precip}
              class="mt-0.5"
            />
            <span>
              Modeled rainfall for each pivot's location
              <span class="block text-ink-muted">Your own gauge readings replace it on the days you enter them.</span>
            </span>
          </label>
          <label class="flex items-start gap-3 text-sm">
            <input
              type="radio"
              name="group[use_model_precip]"
              value="false"
              checked={!group.use_model_precip}
              class="mt-0.5"
            />
            <span>Only the rain we enter</span>
          </label>
          <p class="text-xs text-ink-muted">
            A field can have its own setting, on its page. The forecast's rain counts in the days ahead either way.
          </p>
        </fieldset>
        <Button type="submit" disabled={processing}>Save</Button>
      {/snippet}
    </Form>
  {:else}
    <dl class="grid gap-x-6 gap-y-1 text-sm sm:grid-cols-[max-content_1fr]">
      <dt class="text-ink-muted">Rainfall</dt>
      <dd>
        {group.use_model_precip
          ? "Modeled for each pivot's location, replaced by gauge readings when entered"
          : 'Only the rain entered'}
      </dd>
    </dl>
    <p class="text-sm text-ink-muted">
      Only owners can change the operation's name and rainfall setting; a field can have its own rainfall setting, on
      its page.
    </p>
  {/if}
</section>

<section class="space-y-4 rounded-lg border border-line bg-surface-raised p-6">
  <div>
    <h2 class="text-lg font-medium">Members</h2>
    <p class="text-sm text-ink-muted">
      Everyone here sees and works on the same farms. Owners can also change the settings above, add and remove members,
      and delete farms, pivots, fields or the whole operation. An operation always has at least one owner.
    </p>
  </div>

  <ul class="divide-y divide-line rounded-md border border-line">
    {#each members as member (member.id)}
      <li class="flex flex-wrap items-center justify-between gap-x-4 gap-y-2 px-4 py-3 text-sm">
        <div class="min-w-0">
          <div class="font-medium">
            {member.name ?? member.email}
            {#if member.id === membership_id}<span class="font-normal text-ink-muted">(you)</span>{/if}
          </div>
          <div class="text-xs text-ink-muted">
            {#if member.name}{member.email}{' · '}{/if}{member.owner ? 'Owner' : 'Member'} since {formatDate(
              member.created_at,
              { year: true },
            )}
          </div>
        </div>
        <div class="flex items-center gap-1">
          <!-- The last owner stays an owner and can't leave; the server checks this too -->
          {#if owner && !lastOwner(member)}
            <Button variant="ghost" class="!px-2 !py-1" onclick={() => setRole(member, !member.owner)}>
              {member.owner ? 'Make member' : 'Make owner'}
            </Button>
          {/if}
          {#if (member.id === membership_id || owner) && !lastOwner(member) && members.length > 1}
            <Button variant="danger-ghost" class="!px-2 !py-1" onclick={() => remove(member)}>
              {member.id === membership_id ? 'Leave' : 'Remove'}
            </Button>
          {/if}
        </div>
      </li>
    {/each}
  </ul>

  {#if owner}
    <Form action={memberships.create()} resetOnSuccess options={{ preserveScroll: true }} class="space-y-3">
      {#snippet children({ errors, processing })}
        <h3 class="font-medium">Add someone</h3>
        <div class="grid items-start gap-3 sm:grid-cols-[1fr_10rem_auto]">
          <TextField
            label="Email"
            name="membership[email]"
            type="email"
            autocomplete="off"
            error={errors.email}
            hint="The email they sign in to WISP with. They need an account first."
          />
          <SelectField
            label="Role"
            name="membership[owner]"
            value="false"
            options={[
              { value: 'false', label: 'Member' },
              { value: 'true', label: 'Owner' },
            ]}
          />
          <Button type="submit" class="sm:mt-6" disabled={processing}>Add</Button>
        </div>
      {/snippet}
    </Form>
  {/if}
</section>

<section class="space-y-4 rounded-lg border border-line bg-surface-raised p-6">
  <div>
    <h2 class="text-lg font-medium">Your operations</h2>
    <p class="text-sm text-ink-muted">Switch between operations here or from the menu at the top of the page.</p>
  </div>
  <ul class="divide-y divide-line rounded-md border border-line">
    {#each operations as operation (operation.id)}
      <li class="flex items-center justify-between gap-4 px-4 py-3 text-sm">
        <div>
          <div class="font-medium">{operation.name}</div>
          <div class="text-xs text-ink-muted">
            {operation.owner ? 'Owner' : 'Member'} · {plural(operation.members, 'member')}
          </div>
        </div>
        {#if operation.id === group.id}
          <span class="text-xs text-ink-muted">Current</span>
        {:else}
          <Button variant="secondary" class="!px-3 !py-1" onclick={() => switchTo(operation.id)}>Switch</Button>
        {/if}
      </li>
    {/each}
  </ul>
  <Form action={groups.create()} class="space-y-3" resetOnSuccess>
    {#snippet children({ errors, processing })}
      <div class="grid items-start gap-3 sm:grid-cols-[1fr_auto]">
        <TextField label="Start a new operation" name="group[name]" placeholder="Operation name" error={errors.name} />
        <Button type="submit" variant="secondary" class="sm:mt-6" disabled={processing}>Create</Button>
      </div>
    {/snippet}
  </Form>
</section>

{#if owner}
  <section class="space-y-3 rounded-lg border border-status-irrigate/40 bg-surface-raised p-6">
    <h2 class="text-lg font-medium">Delete this operation</h2>
    <p class="text-sm text-ink-muted">
      Permanently deletes {group.name}, its {setupSummary}, and every entry in them{members.length > 1
        ? `, for all ${members.length} members`
        : ''}.
    </p>
    <Button variant="danger" onclick={() => (deleteOpen = true)}>Delete operation</Button>
  </section>

  <Dialog bind:open={deleteOpen} title="Delete {group.name}?" description="This can't be undone.">
    <div class="space-y-4 text-sm">
      <p>
        This deletes {setupSummary}, with their crops, irrigation and other entries.
        {#if members.length > 1}{plural(members.length - 1, 'other member')} will lose access too.{/if}
      </p>
      <div class="flex justify-end gap-2">
        <Button variant="secondary" onclick={() => (deleteOpen = false)}>Cancel</Button>
        <Button variant="danger" disabled={deleting} onclick={destroy}>Delete {group.name}</Button>
      </div>
    </div>
  </Dialog>
{/if}
