<script lang="ts">
  import type { Snippet } from 'svelte'
  import { Link, page, router } from '@inertiajs/svelte'
  import { DropdownMenu } from 'bits-ui'

  import FlashMessages from '@/lib/components/FlashMessages.svelte'
  import Logo from '@/lib/components/Logo.svelte'
  import { adminWeather, currentGroups, dashboard, settings, usersSessions } from '@/routes'

  let { children }: { children: Snippet } = $props()

  const auth = $derived(page.props.auth)

  const nav = $derived([
    { label: 'Dashboard', route: dashboard.show() },
    ...(auth.user?.admin ? [{ label: 'Weather', route: adminWeather.show() }] : []),
  ])

  const isCurrent = (url: string) => page.url === url || page.url.startsWith(`${url}?`)

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
  <header class="border-b border-line bg-surface-raised">
    <div class="mx-auto flex max-w-6xl flex-wrap items-center gap-x-6 gap-y-2 px-4 py-3">
      <Link href={dashboard.show()} class="text-ink"><Logo /></Link>

      <nav aria-label="Main" class="flex gap-1">
        {#each nav as item (item.label)}
          <Link
            href={item.route}
            class="rounded-md px-3 py-1.5 text-sm font-medium
              {isCurrent(item.route.url) ? 'bg-brand-50 text-brand-700' : 'text-ink-muted hover:text-ink'}"
            aria-current={isCurrent(item.route.url) ? 'page' : undefined}
          >
            {item.label}
          </Link>
        {/each}
      </nav>

      <div class="ml-auto flex items-center gap-2">
        {#if auth.groups.length > 1}
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
    Wisconsin Irrigation Scheduling Program · University of Wisconsin–Madison
  </footer>
</div>
