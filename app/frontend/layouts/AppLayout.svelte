<script lang="ts">
  import type { Snippet } from 'svelte'
  import { Form, Link, page, router } from '@inertiajs/svelte'
  import { DropdownMenu } from 'bits-ui'
  import { MediaQuery } from 'svelte/reactivity'

  import BrandBar from '@/lib/components/BrandBar.svelte'
  import FlashMessages from '@/lib/components/FlashMessages.svelte'
  import Logo from '@/lib/components/Logo.svelte'
  import {
    about,
    adminUsers,
    adminWeather,
    alerts,
    currentGroups,
    dailyEntries,
    dashboard,
    fieldGroups,
    groups,
    impersonations,
    map,
    newUserRegistration,
    newUserSession,
    settings,
    setup,
    usersSessions,
  } from '@/routes'

  let { children }: { children: Snippet } = $props()

  const auth = $derived(page.props.auth)
  // Wider screens have the operation switcher beside the account menu; narrower ones put it in
  // the menu. Left out rather than hidden, as the menu's arrow keys would stop on hidden items.
  const wideNav = new MediaQuery('min-width: 640px')

  // Signed out (the landing and About pages), the nav is just About
  const nav = $derived(
    auth.user
      ? [
          // A pivot's and a field's pages are reached from the dashboard; creating and editing them is setup
          { label: 'Dashboard', route: dashboard.show(), also: [/^\/(pivots|fields)\/\d+(\?|$)/] },
          { label: 'Map', route: map.show() },
          { label: 'Daily entry', route: dailyEntries.show() },
          { label: 'Alerts', route: alerts.show() },
          {
            label: 'Setup',
            route: setup.show(),
            also: [fieldGroups.index().url, /^\/pivots\/(new|\d+\/edit)/, '/setup'],
          },
          { label: 'About', route: about() },
          ...(auth.user.admin
            ? [
                { label: 'Weather', route: adminWeather.show() },
                { label: 'Users', route: adminUsers.index(), also: ['/admin/users/'] },
              ]
            : []),
        ]
      : [{ label: 'About', route: about() }],
  )

  // While an admin is signed in as someone else, every tab's title says whose WISP it is. Pages set
  // their titles in <svelte:head>, so this re-adds the prefix whenever a page changes its title.
  const titlePrefix = $derived(auth.impersonator && auth.user ? `As ${auth.user.email} · ` : null)
  $effect(() => {
    void page.url
    const prefix = titlePrefix
    if (!prefix) return
    const apply = () => {
      if (!document.title.startsWith(prefix)) document.title = prefix + document.title
    }
    apply()
    const observer = new MutationObserver(apply)
    observer.observe(document.head, { childList: true, subtree: true, characterData: true })
    return () => observer.disconnect()
  })

  // The map takes the whole window below the header, with no footer
  const wide = $derived(page.component.startsWith('Map/'))

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

<div class="flex flex-col {wide ? 'h-dvh' : 'min-h-dvh'}">
  <!-- The first stop for keyboard users, past the branding and the nav (WCAG 2.4.1) -->
  <a
    href="#main"
    class="sr-only rounded-md bg-surface-raised px-3 py-2 text-sm font-medium text-brand-600 shadow-lg focus:not-sr-only focus:fixed focus:top-2 focus:left-2 focus:z-60"
    >Skip to main content</a
  >
  {#if auth.impersonator && auth.user}
    <!-- Signed in as someone else for support: stays at the top as the page scrolls (PLAN.md Phase 8 B) -->
    <div role="status" class="sticky top-0 z-50 bg-impersonation text-on-impersonation">
      <div class="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-x-4 gap-y-1 px-4 py-2 text-sm">
        <p>
          Signed in as <strong>{auth.user.display_name}</strong>{auth.user.display_name === auth.user.email
            ? ''
            : ` (${auth.user.email})`} for support
        </p>
        <Form action={impersonations.destroy()}>
          {#snippet children({ processing })}
            <button
              type="submit"
              disabled={processing}
              class="rounded-md border border-on-impersonation px-3 py-1 font-medium hover:bg-on-impersonation/15 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-on-impersonation disabled:opacity-70"
              >Return to admin</button
            >
          {/snippet}
        </Form>
      </div>
    </div>
  {/if}
  <BrandBar />
  <header class="border-b border-line bg-surface-raised">
    <div class="mx-auto flex max-w-6xl flex-wrap items-center gap-x-6 gap-y-2 px-4 py-3">
      <Link href={dashboard.show()} class="flex text-ink"><Logo /></Link>

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
                aria-label="{auth.group?.name}, switch operation"
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
                  <DropdownMenu.Separator class="my-1 h-px bg-line" />
                  <DropdownMenu.Item class={menuItem} onSelect={() => router.visit(groups.show().url)}>
                    <span class="w-5"></span>Manage operations
                  </DropdownMenu.Item>
                </DropdownMenu.Content>
              </DropdownMenu.Portal>
            </DropdownMenu.Root>
          </div>
        {:else if auth.group}
          <span class="hidden text-sm text-ink-muted sm:inline">{auth.group.name}</span>
        {/if}

        {#if !auth.user}
          <Link href={newUserSession()} class="rounded-md px-3 py-1.5 text-sm font-medium text-ink-muted hover:text-ink"
            >Sign in</Link
          >
          <Link
            href={newUserRegistration()}
            class="rounded-md bg-brand-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-brand-700 dark:text-surface"
          >
            Create account
          </Link>
        {:else}
          <DropdownMenu.Root>
            <DropdownMenu.Trigger
              class="rounded-full bg-brand-100 px-3 py-1.5 text-sm font-medium text-brand-700 hover:bg-brand-50"
              aria-label="{auth.user?.display_name}, account menu"
            >
              {auth.user?.display_name}
            </DropdownMenu.Trigger>
            <DropdownMenu.Portal>
              <DropdownMenu.Content class={menuContent} sideOffset={6} align="end">
                {#if auth.groups.length > 1 && !wideNav.current}
                  <DropdownMenu.Group aria-label="Operation">
                    <DropdownMenu.GroupHeading class="px-3 pt-1 pb-1 text-xs text-ink-muted"
                      >Operation</DropdownMenu.GroupHeading
                    >
                    {#each auth.groups as group (group.id)}
                      <DropdownMenu.Item class={menuItem} onSelect={() => switchGroup(group.id)}>
                        <span class="w-5">{group.id === auth.group?.id ? '✓' : ''}</span>{group.name}
                      </DropdownMenu.Item>
                    {/each}
                    <DropdownMenu.Separator class="my-1 h-px bg-line" />
                  </DropdownMenu.Group>
                {/if}
                <DropdownMenu.Item class={menuItem} onSelect={() => router.visit(groups.show().url)}>
                  Operation and members
                </DropdownMenu.Item>
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
        {/if}
      </div>
    </div>
  </header>

  {#if wide}
    <main id="main" tabindex="-1" class="flex min-h-0 flex-1 flex-col outline-none">
      <FlashMessages />
      {@render children()}
    </main>
  {:else}
    <main id="main" tabindex="-1" class="mx-auto w-full max-w-6xl flex-1 space-y-4 px-4 py-6 outline-none">
      <FlashMessages />
      {@render children()}
    </main>

    <footer class="space-y-1 border-t border-line px-4 py-4 text-center text-xs text-ink-muted">
      <p>Wisconsin Irrigation Scheduling Program</p>
      <p>
        Developed by the <a href="https://cals.wisc.edu/" class="underline hover:text-ink"
          >College of Agricultural and Life Sciences</a
        > at the University of Wisconsin–Madison.
      </p>
    </footer>
  {/if}
</div>
