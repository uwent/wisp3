# A perennial planting's cuttings (alfalfa, mint): each restarts its canopy (PLAN.md Phase 8 G.3)
class CreateCanopyCuttings < ActiveRecord::Migration[8.1]
  def change
    create_table :canopy_cuttings do |t|
      t.references :planting, null: false, foreign_key: {on_delete: :cascade}
      t.date :date, null: false
      t.timestamps
    end
    add_index :canopy_cuttings, [:planting_id, :date], unique: true
  end
end
