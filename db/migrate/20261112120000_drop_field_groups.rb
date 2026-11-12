# Field groups are retired (PLAN.md Phase 8 G.4): pivot groups and daily entry's rain fill-down
# replace them. Their entries first become their member fields' own, wherever the field had none, so
# every balance reads as before: rain and soil moisture where the field entered none (a group's
# came next), irrigation only where the pivot didn't irrigate the field that day either (a pivot's
# came before the group's). Where a field was in several groups, the oldest group's entry counts,
# as DailyInputs read them. Notes stay behind.
class DropFieldGroups < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      WITH group_values AS (
        SELECT DISTINCT ON (members.field_id, entries.date)
          members.field_id, entries.date, entries.rain_in, entries.irrigation_in, entries.soil_moisture_pct
        FROM field_group_entries entries
        JOIN field_group_members members ON members.field_group_id = entries.field_group_id
        ORDER BY members.field_id, entries.date, entries.field_group_id
      ), field_values AS (
        SELECT group_values.field_id, group_values.date, group_values.rain_in, group_values.soil_moisture_pct,
          CASE WHEN EXISTS (
            SELECT 1 FROM pivot_irrigations
            JOIN fields ON fields.pivot_id = pivot_irrigations.pivot_id
            WHERE fields.id = group_values.field_id AND pivot_irrigations.date = group_values.date
              AND (pivot_irrigations.field_ids IS NULL OR group_values.field_id = ANY (pivot_irrigations.field_ids))
          ) THEN NULL ELSE group_values.irrigation_in END AS irrigation_in
        FROM group_values
      )
      INSERT INTO field_entries (field_id, date, rain_in, irrigation_in, soil_moisture_pct, created_at, updated_at)
      SELECT field_id, date, rain_in, irrigation_in, soil_moisture_pct, now(), now()
      FROM field_values
      WHERE rain_in IS NOT NULL OR irrigation_in IS NOT NULL OR soil_moisture_pct IS NOT NULL
      ON CONFLICT (field_id, date) DO UPDATE SET
        rain_in = COALESCE(field_entries.rain_in, EXCLUDED.rain_in),
        irrigation_in = COALESCE(field_entries.irrigation_in, EXCLUDED.irrigation_in),
        soil_moisture_pct = COALESCE(field_entries.soil_moisture_pct, EXCLUDED.soil_moisture_pct),
        updated_at = now()
    SQL

    drop_table :field_group_entries
    drop_table :field_group_members
    drop_table :field_groups
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "field groups are retired; their values are in field entries"
  end
end
