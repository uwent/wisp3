import type { SharedProps } from '@/types'

// Who may delete a planting or an irrigation group (G.15): the operation's owners, or the member
// who added it (PlantingsController and PivotGroupsController check the same)
export function mayDelete(record: { created_by_id: number | null }, auth: SharedProps['auth']): boolean {
  return auth.owner || (record.created_by_id !== null && record.created_by_id === auth.user?.id)
}
