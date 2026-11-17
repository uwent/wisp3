import type { Group, User } from './serializers'
export type * from './serializers'

export type FlashData = {
  notice?: string
  alert?: string
}

// Props shared with every page (InertiaController.inertia_share)
export type SharedProps = {
  // Today's date on the server (Central time), ISO; read it through today() in lib/dates.ts
  today: string
  auth: {
    user: User | null
    group: Group | null
    owner: boolean
    groups: Group[]
    // The admin signed in as this user for support (PLAN.md Phase 8 B), or null
    impersonator: { name: string; email: string } | null
  }
  // Viewing the example farm (PLAN.md G.8): its day, which is today on every page; null otherwise.
  // Pages are read-only then (isExample in lib/permissions.ts).
  example: { as_of: string } | null
}
