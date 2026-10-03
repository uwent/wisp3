# Loads plants and soil types from db/reference/*.yml, adding new rows and updating changed
# ones by key. Idempotent; runs from db/seeds.rb and on every deploy.
module ReferenceData
  module_function

  def load!
    upsert(Plant, "plants.yml")
    upsert(SoilType, "soil_types.yml")
  end

  def upsert(model, file)
    rows = YAML.load_file(Rails.root.join("db/reference", file))
    columns = model.column_names - %w[id created_at updated_at]
    model.upsert_all(rows.map { |row| columns.index_with { |column| row[column] } }, unique_by: :key)
  end
end
