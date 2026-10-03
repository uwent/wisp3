// Dates arrive from Rails as ISO strings ("2026-07-01"). They are calendar dates, not instants, so
// they're handled as UTC midnights to avoid shifting a day in the browser's time zone.

export function parseDate(iso: string): Date {
  const [year, month, day] = iso.slice(0, 10).split('-').map(Number)
  return new Date(Date.UTC(year, month - 1, day))
}

export function isoDate(date: Date): string {
  return date.toISOString().slice(0, 10)
}

export function addDays(iso: string, days: number): string {
  const date = parseDate(iso)
  date.setUTCDate(date.getUTCDate() + days)
  return isoDate(date)
}

export function daysBetween(from: string, to: string): number {
  return Math.round((parseDate(to).getTime() - parseDate(from).getTime()) / 86_400_000)
}

/** "Jul 1"; with year: "Jul 1, 2026"; with weekday: "Wed, Jul 1" */
export function formatDate(iso: string | null | undefined, options: { year?: boolean; weekday?: boolean } = {}) {
  if (!iso) return '—'
  return parseDate(iso).toLocaleDateString('en-US', {
    timeZone: 'UTC',
    month: 'short',
    day: 'numeric',
    ...(options.year ? { year: 'numeric' } : {}),
    ...(options.weekday ? { weekday: 'short' } : {}),
  })
}

/** "today", "yesterday", "3 days ago" relative to today (ISO) */
export function relativeDay(iso: string, today: string): string {
  const days = daysBetween(iso, today)
  if (days === 0) return 'today'
  if (days === 1) return 'yesterday'
  if (days === -1) return 'tomorrow'
  return days > 0 ? `${days} days ago` : `in ${-days} days`
}
