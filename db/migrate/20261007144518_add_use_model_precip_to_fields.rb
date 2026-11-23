class AddUseModelPrecipToFields < ActiveRecord::Migration[8.1]
  # NULL follows the group's setting (Q7)
  def change
    add_column :fields, :use_model_precip, :boolean
  end
end
