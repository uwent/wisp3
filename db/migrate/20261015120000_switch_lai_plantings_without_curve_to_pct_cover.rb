# LAI is now offered only for crops with an LAI growth curve (PLAN.md Phase 6.7). Plantings of
# other crops on LAI switch to percent cover; their LAI readings are kept (unused) in case a curve
# for the crop is added later.
class SwitchLaiPlantingsWithoutCurveToPctCover < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE plantings SET et_method = 'pct_cover', updated_at = now()
      FROM plants
      WHERE plantings.plant_id = plants.id AND plantings.et_method = 'lai' AND plants.canopy_model IS NULL
    SQL
  end

  def down
    # Which plantings were switched isn't recorded
  end
end
