# FAO-56's dual crop coefficient (C22): each crop's basal coefficients at mid season and
# at harvest (Table 17), and each soil texture's readily evaporable water (Table 19, inches), filled
# from db/reference/plants.yml and soil_types.yml by ReferenceData on db:seed (which every deploy
# runs after migrating)
class AddDualCropCoefficients < ActiveRecord::Migration[8.1]
  def change
    add_column :plants, :kcb_mid, :float
    add_column :plants, :kcb_end, :float
    add_column :soil_types, :rew_in, :float
  end
end
