# Vine kill (potato): from this date the canopy ramps down to 0% over two weeks, while the balance
# runs on to the harvest (end_date), as growers irrigate through vine kill for skin set. NULL for
# crops that aren't vine killed, and for potatoes before it's planned.
class AddVineKillDateToPlantings < ActiveRecord::Migration[8.1]
  def change
    add_column :plantings, :vine_kill_date, :date
    add_check_constraint :plantings, "vine_kill_date IS NULL OR (emergence_date <= vine_kill_date AND vine_kill_date <= end_date)",
      name: "plantings_vine_kill_order"
  end
end
