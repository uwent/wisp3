# PLAN.md Phase 8 G.14 part 7(b): a planting keeps the irrigation system its season ran on, as it
# keeps its weather cell (G.9), so a field can move to another system without taking its earlier
# seasons' irrigation with it. Filled from each planting's field as it is now.
class AddPivotToPlantings < ActiveRecord::Migration[8.1]
  def up
    add_reference :plantings, :pivot, foreign_key: true

    execute <<~SQL
      UPDATE plantings
      SET pivot_id = fields.pivot_id
      FROM fields
      WHERE fields.id = plantings.field_id
    SQL

    change_column_null :plantings, :pivot_id, false
  end

  def down
    remove_reference :plantings, :pivot, foreign_key: true
  end
end
