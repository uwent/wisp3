class AddRainfedToPlantings < ActiveRecord::Migration[8.1]
  def change
    add_column :plantings, :rainfed, :boolean, default: false, null: false
  end
end
