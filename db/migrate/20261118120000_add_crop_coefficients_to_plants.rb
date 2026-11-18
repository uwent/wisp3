# Each crop's FAO-56 mid-season crop coefficient and height (PLAN.md §9 C21, Q11), filled from
# db/reference/plants.yml by ReferenceData on db:seed (which every deploy runs after migrating)
class AddCropCoefficientsToPlants < ActiveRecord::Migration[8.1]
  def change
    add_column :plants, :kc_mid, :float
    add_column :plants, :crop_height_m, :float
  end
end
