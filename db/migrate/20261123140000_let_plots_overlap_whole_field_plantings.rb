# A plot may overlap a whole-field planting (D19): the exclusion constraint covers whole-field
# plantings only, which can't overlap each other
class LetPlotsOverlapWholeFieldPlantings < ActiveRecord::Migration[8.1]
  OLD = "field_id WITH =, daterange(season_start, end_date, '[]') WITH &&, " \
    "(CASE WHEN partial THEN int8range(id, id + 1) ELSE int8range(NULL, NULL) END) WITH &&"
  NEW = "field_id WITH =, daterange(season_start, end_date, '[]') WITH &&"

  def up
    remove_exclusion_constraint :plantings, OLD, using: :gist, name: "plantings_no_overlap"
    add_exclusion_constraint :plantings, NEW, using: :gist, where: "NOT partial", name: "plantings_no_overlap"
  end

  # Fails while a plot overlaps a whole-field planting: end or delete those first
  def down
    remove_exclusion_constraint :plantings, NEW, using: :gist, where: "NOT partial", name: "plantings_no_overlap"
    add_exclusion_constraint :plantings, OLD, using: :gist, name: "plantings_no_overlap"
  end
end
