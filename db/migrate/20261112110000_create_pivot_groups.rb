# Pivots on one farm that share a rain gauge (PLAN.md Phase 8 G.4): daily entry fills a group's rain
# into its pivots' fields. A pivot is in at most one group, on its own farm.
class CreatePivotGroups < ActiveRecord::Migration[8.1]
  def change
    create_table :pivot_groups do |t|
      t.references :farm, null: false, foreign_key: {on_delete: :cascade}
      t.string :name, null: false
      t.timestamps
    end
    # For the pivots' composite foreign key, which keeps a pivot's group on the pivot's farm
    add_index :pivot_groups, [:id, :farm_id], unique: true

    add_column :pivots, :pivot_group_id, :bigint
    add_index :pivots, :pivot_group_id
    # No ON DELETE action: PivotGroup ungroups its pivots before it's deleted, and a farm's pivots
    # go with it
    add_foreign_key :pivots, :pivot_groups, column: [:pivot_group_id, :farm_id], primary_key: [:id, :farm_id],
      name: "pivots_pivot_group_same_farm"
  end
end
