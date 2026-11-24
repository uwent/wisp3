<script lang="ts">
  import type { Snippet } from 'svelte'
  import { Form, Link, page, router } from '@inertiajs/svelte'
  import { DropdownMenu } from 'bits-ui'
  import { MediaQuery } from 'svelte/reactivity'

  import BrandBar from '@/lib/components/BrandBar.svelte'
  import { menuContent, menuItem } from '@/lib/components/menu'
  import FlashMessages from '@/lib/components/FlashMessages.svelte'
  import Logo from '@/lib/components/Logo.svelte'
  import { formatDate } from '@/lib/dates'
  import { forgetAllKept } from '@/lib/outlines/kept'
  import { stickyHeight } from '@/lib/stickyBars'
  import {
    about,
    adminUsers,
    alerts,
    currentGroups,
    dailyEntries,
    dashboard,
    examples,
    groups,
    impersonations,
    map,
    newUserRegistration,
    newUserSession,
    settings,
    setup,
    usersSessions,
    weatherZones,
  } from '@/routes'

  let { children }: { children: Snippet } = $props()

  const auth = $derived(page.props.auth)
  // Viewing the example farm: its pages only, with a bar saying so
  const example = $derived(page.props.example)
  // Wider screens have the operation switcher beside the account menu; narrower ones put it in
  // the menu. Left out rather than hidden, as the menu's arrow keys would stop on hidden items.
  const wideNav = new MediaQuery('min-width: 640px')

  // Signed out (the landing and About pages), the nav is the example farm and About; viewing the
  // example, its pages
  const nav = $derived(
    example
      ? [
          { label: 'Dashboard', route: dashboard.show(), also: [/^\/(systems|fields|plantings)\/\d+(\?|$)/] },
          { label: 'Map', route: map.show() },
          { label: 'Weather', route: weatherZones.index(), also: ['/weather/'] },
          { label: 'About', route: about() },
        ]
      : auth.user
        ? [
            // A system's, a field's and a planting's pages are reached from the dashboard; creating and editing them is setup
            { label: 'Dashboard', route: dashboard.show(), also: [/^\/(systems|fields|plantings)\/\d+(\?|$)/] },
            { label: 'Map', route: map.show() },
            { label: 'Daily entry', route: dailyEntries.show() },
            { label: 'Weather', route: weatherZones.index(), also: ['/weather/'] },
            { label: 'Alerts', route: alerts.show() },
            {
              label: 'Setup',
              route: setup.show(),
              also: [/^\/systems\/(new|\d+\/edit)/, '/setup'],
            },
            { label: 'About', route: about() },
            // Users and Weather data, switched between by AdminTabs
            ...(auth.user.admin ? [{ label: 'Admin', route: adminUsers.index(), also: ['/admin/'] }] : []),
          ]
        : [
            { label: 'Example farm', route: examples.show() },
            { label: 'About', route: about() },
          ],
  )

  // On phones the nav scrolls sideways: fade the edge that has more tabs past it, and bring the
  // current tab into view after each visit (Setup is off the right edge at 390 px)
  let navEl = $state<HTMLElement>()
  let moreLeft = $state(false)
  let moreRight = $state(false)
  function measureNav() {
    if (!navEl) return
    moreLeft = navEl.scrollLeft > 1
    moreRight = navEl.scrollLeft + navEl.clientWidth < navEl.scrollWidth - 1
  }
  $effect(() => {
    if (!navEl) return
    const observer = new ResizeObserver(measureNav)
    observer.observe(navEl)
    return () => observer.disconnect()
  })
  $effect(() => {
    void page.url
    const current = navEl?.querySelector<HTMLElement>('[aria-current="page"]')
    if (navEl && current && navEl.scrollWidth > navEl.clientWidth) {
      navEl.scrollLeft = current.offsetLeft - (navEl.clientWidth - current.offsetWidth) / 2
    }
    measureNav()
  })
  const fade = '2.5rem'
  const navMask = $derived(
    moreLeft || moreRight
      ? `linear-gradient(to right, ${moreLeft ? `transparent, black ${fade}` : 'black'}, ${
          moreRight ? `black calc(100% - ${fade}), transparent` : 'black'
        })`
      : undefined,
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
</script>

<div class="flex flex-col {wide ? 'h-dvh' : 'min-h-dvh'}">
  <!-- The first stop for keyboard users, past the branding and the nav (WCAG 2.4.1) -->
  <a
    href="#main"
    class="sr-only rounded-md bg-surface-raised px-3 py-2 text-sm font-medium text-brand-600 shadow-lg focus:not-sr-only focus:fixed focus:top-2 focus:left-2 focus:z-60"
    >Skip to main content</a
  >
  {#if auth.impersonator && auth.user}
    <!-- Signed in as someone else for support: stays at the top as the page scrolls -->
    <div
      role="status"
      class="sticky top-0 z-50 bg-impersonation text-on-impersonation"
      {@attach stickyHeight('--app-bar-h')}
    >
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
  {#if example}
    <!-- Viewing the example farm: stays at the top as the page scrolls -->
    <div role="status" class="sticky top-0 z-50 bg-example text-on-example" {@attach stickyHeight('--app-bar-h')}>
      <div class="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-x-4 gap-y-1 px-4 py-2 text-sm">
        <p>
          You're viewing an example farm as of <strong>{formatDate(example.as_of, { year: true })}</strong>{auth.user
            ? '. It can be viewed but not changed.'
            : '. Create an account to set up your own.'}
        </p>
        <Form action={examples.destroy()}>
          {#snippet children({ processing })}
            <button
              type="submit"
              disabled={processing}
              class="rounded-md border border-on-example px-3 py-1 font-medium hover:bg-on-example/15 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-on-example disabled:opacity-70"
              >Leave the example</button
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
      <nav
        bind:this={navEl}
        aria-label="Main"
        class="order-3 -mx-1 flex w-full gap-1 overflow-x-auto sm:order-2 sm:w-auto"
        style:mask-image={navMask}
        onscroll={measureNav}
      >
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
        {#if example}
          <span class="hidden text-sm text-ink-muted sm:inline">{auth.group?.name}</span>
        {:else if auth.groups.length > 1}
          <div class="hidden sm:block">
            <DropdownMenu.Root>
              <DropdownMenu.Trigger
                class="rounded-md border border-line px-3 py-1.5 text-sm hover:bg-surface"
                aria-label="{auth.group?.name}, switch operation"
              >
                {auth.group?.name} ▾
              </DropdownMenu.Trigger>
              <DropdownMenu.Portal>
                <DropdownMenu.Content class={menuContent} sideOffset={6} align="end" preventScroll={false}>
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
              <DropdownMenu.Content class={menuContent} sideOffset={6} align="end" preventScroll={false}>
                {#if auth.groups.length > 1 && !wideNav.current && !example}
                  <DropdownMenu.Group aria-label="Operation">
                    <DropdownMenu.GroupHeading class="px-3 py-1 text-xs text-ink-muted"
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
                  onSelect={() => {
                    forgetAllKept()
                    router.visit(usersSessions.destroy().url, { method: 'delete' })
                  }}
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

    <footer class="space-y-1 border-t border-line p-4 text-center text-xs text-ink-muted">
      <p>Wisconsin Irrigation Scheduling Program</p>
      <p>
        Developed by the <a href="https://cals.wisc.edu/" class="underline hover:text-ink"
          >College of Agricultural and Life Sciences</a
        > at the University of Wisconsin–Madison.
      </p>
    </footer>
  {/if}
</div>
