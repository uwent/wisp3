# Who made a planting or an irrigation group, so they may delete it as well as the group's owners.
# NULL for those made before, and when the user is deleted: owners only.
class AddCreatedByToPlantingsAndPivotGroups < ActiveRecord::Migration[8.1]
  def change
    add_reference :plantings, :created_by, foreign_key: {to_table: :users, on_delete: :nullify}
    add_reference :pivot_groups, :created_by, foreign_key: {to_table: :users, on_delete: :nullify}
  end
end
