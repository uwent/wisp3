# The days each account used WISP and which parts of it (PLAN.md H.2), for the admin Usage page
class CreateActivityDays < ActiveRecord::Migration[8.1]
  def change
    create_table :activity_days do |t|
      t.references :user, null: false, foreign_key: {on_delete: :cascade}, index: false
      t.date :date, null: false
      t.string :areas, array: true, null: false, default: []
      t.boolean :phone, null: false, default: false
    end
    add_index :activity_days, [:user_id, :date], unique: true
    add_index :activity_days, :date
  end
end
