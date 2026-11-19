# The rainfall setting (Q7) moves from the operation and its fields to farms (a compact area, often
# with its own rain) and irrigation groups (the systems sharing a rain gauge), 2026-11-19. A farm's
# starts as its operation's; a group's NULL follows its farm's. No field had its own in production
# (not yet announced).
class MoveRainfallSettingToFarmsAndPivotGroups < ActiveRecord::Migration[8.1]
  def up
    add_column :farms, :use_model_precip, :boolean, default: true, null: false
    execute "UPDATE farms SET use_model_precip = groups.use_model_precip FROM groups WHERE groups.id = farms.group_id"
    add_column :pivot_groups, :use_model_precip, :boolean
    remove_column :groups, :use_model_precip
    remove_column :fields, :use_model_precip
  end

  def down
    add_column :fields, :use_model_precip, :boolean
    add_column :groups, :use_model_precip, :boolean, default: true, null: false
    execute "UPDATE groups SET use_model_precip = false WHERE id IN (SELECT group_id FROM farms WHERE NOT use_model_precip)"
    remove_column :pivot_groups, :use_model_precip
    remove_column :farms, :use_model_precip
  end
end
