<script lang="ts">
  import type { Snippet } from 'svelte'
  import { Link, page, router } from '@inertiajs/svelte'
  import { DropdownMenu } from 'bits-ui'

  import BrandBar from '@/lib/components/BrandBar.svelte'
  import FlashMessages from '@/lib/components/FlashMessages.svelte'
  import Logo from '@/lib/components/Logo.svelte'
  import { adminUsers, adminWeather, currentGroups, dailyEntries, dashboard, fieldGroups, settings, setup, usersSessions } from '@/routes'

  let { children }: { children: Snippet } = $props()

  const auth = $derived(page.props.auth)

  const nav = $derived([
    // A pivot's and a field's pages are reached from the dashboard; creating and editing them is setup
    { label: 'Dashboard', route: dashboard.show(), also: [/^\/(pivots|fields)\/\d+(\?|$)/] },
    { label: 'Daily entry', route: dailyEntries.show() },
    { label: 'Setup', route: setup.show(), also: [fieldGroups.index().url, /^\/pivots\/(new|\d+\/edit)/, '/setup'] },
    ...(auth.user?.admin
      ? [
          { label: 'Weather', route: adminWeather.show() },
          { label: 'Users', route: adminUsers.index(), also: ['/admin/users/'] },
        ]
      : []),
  ])

  const isCurrent = (url: string, also: (string | RegExp)[] = []) =>
    page.url === url ||
    page.url.startsWith(`${url}?`) ||
    also.some((match) => (typeof match === 'string' ? page.url.startsWith(match) : match.test(page.url)))

  function switchGroup(groupId: number) {
    const { url, method } = currentGroups.update()
    router.visit(url, { method, data: { group_id: groupId } })
  }

  const menuContent =
    'z-50 min-w-48 rounded-md border border-line bg-surface-raised p-1 text-sm shadow-lg focus:outline-none'
  const menuItem =
    'flex cursor-pointer select-none items-center rounded px-3 py-2 data-highlighted:bg-brand-50 focus:outline-none'
</script>

<div class="flex min-h-dvh flex-col">
  <BrandBar />
  <header class="border-b border-line bg-surface-raised">
    <div class="mx-auto flex max-w-6xl flex-wrap items-center gap-x-6 gap-y-2 px-4 py-3">
      <Link href={dashboard.show()} class="text-ink"><Logo /></Link>

      <!-- On phones: logo and account menu on one row, the nav below; the group switch moves into the account menu -->
      <nav aria-label="Main" class="order-3 -mx-1 flex w-full gap-1 overflow-x-auto sm:order-2 sm:w-auto">
        {#each nav as item (item.label)}
          <Link
            href={item.route}
            class="shrink-0 rounded-md px-3 py-1.5 text-sm font-medium
              {isCurrent(item.route.url, item.also) ? 'bg-brand-50 text-brand-700' : 'text-ink-muted hover:text-ink'}"
            aria-current={isCurrent(item.route.url, item.also) ? 'page' : undefined}
          >
            {item.label}
          </Link>
        {/each}
      </nav>

      <div class="order-2 ml-auto flex items-center gap-2 sm:order-3">
        {#if auth.groups.length > 1}
          <div class="hidden sm:block">
            <DropdownMenu.Root>
              <DropdownMenu.Trigger
                class="rounded-md border border-line px-3 py-1.5 text-sm hover:bg-surface"
                aria-label="Switch farm operation"
              >
                {auth.group?.name} ▾
              </DropdownMenu.Trigger>
              <DropdownMenu.Portal>
                <DropdownMenu.Content class={menuContent} sideOffset={6} align="end">
                  {#each auth.groups as group (group.id)}
                    <DropdownMenu.Item class={menuItem} onSelect={() => switchGroup(group.id)}>
                      <span class="w-5">{group.id === auth.group?.id ? '✓' : ''}</span>{group.name}
                    </DropdownMenu.Item>
                  {/each}
                </DropdownMenu.Content>
              </DropdownMenu.Portal>
            </DropdownMenu.Root>
          </div>
        {:else if auth.group}
          <span class="hidden text-sm text-ink-muted sm:inline">{auth.group.name}</span>
        {/if}

        <DropdownMenu.Root>
          <DropdownMenu.Trigger
            class="rounded-full bg-brand-100 px-3 py-1.5 text-sm font-medium text-brand-700 hover:bg-brand-50"
            aria-label="Account menu"
          >
            {auth.user?.display_name}
          </DropdownMenu.Trigger>
          <DropdownMenu.Portal>
            <DropdownMenu.Content class={menuContent} sideOffset={6} align="end">
              {#if auth.groups.length > 1}
                <DropdownMenu.Group class="sm:hidden" aria-label="Farm operation">
                  <DropdownMenu.GroupHeading class="px-3 pt-1 pb-1 text-xs text-ink-muted">Farm operation</DropdownMenu.GroupHeading>
                  {#each auth.groups as group (group.id)}
                    <DropdownMenu.Item class={menuItem} onSelect={() => switchGroup(group.id)}>
                      <span class="w-5">{group.id === auth.group?.id ? '✓' : ''}</span>{group.name}
                    </DropdownMenu.Item>
                  {/each}
                  <DropdownMenu.Separator class="my-1 h-px bg-line" />
                </DropdownMenu.Group>
              {/if}
              <DropdownMenu.Item class={menuItem} onSelect={() => router.visit(settings.show().url)}>
                Settings
              </DropdownMenu.Item>
              <DropdownMenu.Separator class="my-1 h-px bg-line" />
              <DropdownMenu.Item
                class={menuItem}
                onSelect={() => router.visit(usersSessions.destroy().url, { method: 'delete' })}
              >
                Sign out
              </DropdownMenu.Item>
            </DropdownMenu.Content>
          </DropdownMenu.Portal>
        </DropdownMenu.Root>
      </div>
    </div>
  </header>

  <main class="mx-auto w-full max-w-6xl flex-1 space-y-4 px-4 py-6">
    <FlashMessages />
    {@render children()}
  </main>

  <footer class="border-t border-line py-4 text-center text-xs text-ink-muted">
    Wisconsin Irrigation Scheduling Program
  </footer>
</div>
