<script lang="ts">
  import { Link, page } from '@inertiajs/svelte'

  import { adminAnnouncements, adminUsage, adminUsers, adminWeather } from '@/routes'

  // The admin pages' pills under the nav's one Admin tab: Users (with each user's pages), Weather
  // data (fetches, health check and corrections; the growers' Weather tab is their zones) and Usage
  // (how growers use WISP) and Announcements (emails to accounts)
  const tabs = [
    { label: 'Users', href: adminUsers.index().url, prefix: '/admin/users' },
    { label: 'Weather data', href: adminWeather.show().url, prefix: '/admin/weather' },
    { label: 'Usage', href: adminUsage.show().url, prefix: '/admin/usage' },
    { label: 'Announcements', href: adminAnnouncements.index().url, prefix: '/admin/announcements' },
  ]
</script>

<nav aria-label="Admin" class="flex flex-wrap gap-1.5">
  {#each tabs as tab (tab.href)}
    {@const current = page.url.startsWith(tab.prefix)}
    <Link
      href={tab.href}
      class="rounded-full border px-3 py-1 text-sm font-medium {current
        ? 'border-brand-600 bg-brand-600 text-white dark:text-surface'
        : 'border-line text-ink-muted hover:border-brand-600 hover:text-ink'}"
      aria-current={current ? 'page' : undefined}>{tab.label}</Link
    >
  {/each}
</nav>
