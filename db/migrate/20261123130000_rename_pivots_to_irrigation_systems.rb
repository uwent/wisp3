# Pivot was the model's name for every irrigation system since travelers, solid set, drip and
# locations joined center pivots and linears; it's IrrigationSystem now (D18), with system_id on
# fields and plantings, and pivot groups are irrigation groups. Postgres renames only the
# catalog, so this is instant. Indexes named by Rails' convention follow the tables and columns;
# the check constraints and the named foreign key are renamed here, and the stored names that
# point at the old ones (digest exclusions' subject type, activity days' area) are rewritten.
class RenamePivotsToIrrigationSystems < ActiveRecord::Migration[8.1]
  CHECKS = %w[arc_both_or_neither point_shape inches_at_100_kind inches_at_100_positive linear_shape
    center_shape kind pump_capacity_positive radius_max radius_positive].freeze

  def change
    rename_table :pivot_groups, :irrigation_groups
    rename_table :pivots, :irrigation_systems
    rename_column :irrigation_systems, :pivot_group_id, :irrigation_group_id
    rename_column :fields, :pivot_id, :system_id
    rename_column :plantings, :pivot_id, :system_id

    reversible do |direction|
      direction.up do
        CHECKS.each { |name| rename_constraint(:irrigation_systems, "pivots_#{name}", "irrigation_systems_#{name}") }
        rename_constraint(:irrigation_systems, "pivots_pivot_group_same_farm", "irrigation_systems_group_same_farm")
        execute "UPDATE digest_exclusions SET subject_type = 'IrrigationSystem' WHERE subject_type = 'Pivot'"
        execute "UPDATE activity_days SET areas = array_replace(areas, 'pivot', 'system') WHERE 'pivot' = ANY(areas)"
      end
      direction.down do
        CHECKS.each { |name| rename_constraint(:irrigation_systems, "irrigation_systems_#{name}", "pivots_#{name}") }
        rename_constraint(:irrigation_systems, "irrigation_systems_group_same_farm", "pivots_pivot_group_same_farm")
        execute "UPDATE digest_exclusions SET subject_type = 'Pivot' WHERE subject_type = 'IrrigationSystem'"
        execute "UPDATE activity_days SET areas = array_replace(areas, 'system', 'pivot') WHERE 'system' = ANY(areas)"
      end
    end
  end

  private

  def rename_constraint(table, from, to)
    execute "ALTER TABLE #{quote_table_name(table)} RENAME CONSTRAINT #{quote_column_name(from)} TO #{quote_column_name(to)}"
  end
end
