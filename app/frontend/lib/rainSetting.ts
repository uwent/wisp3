import { editLink } from '@/lib/setup/links'

// Which rain a balance uses (Q7): set for a farm, and for an irrigation group (the systems
// sharing a rain gauge) that doesn't follow its farm's (IrrigationSystem#use_model_precip?)

/** Where the setting a system follows is changed: its group's dialog in Setup, else its farm's */
export function rainSettingLink(groupId: number | null, farmId: number): string {
  return groupId === null ? editLink('farm', farmId) : editLink('group', groupId)
}

/** Whose setting it is, for "… setting" */
export function rainSettingOwner(group: { name: string } | null): string {
  return group ? `the ${group.name} group's` : "the farm's"
}
