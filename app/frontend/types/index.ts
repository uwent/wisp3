import type { Group, User } from './serializers'
export type * from './serializers'

export type FlashData = {
  notice?: string
  alert?: string
}

// Props shared with every page (InertiaController.inertia_share)
export type SharedProps = {
  auth: {
    user: User | null
    group: Group | null
    owner: boolean
    groups: Group[]
  }
}
