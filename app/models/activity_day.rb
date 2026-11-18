# A day an account used WISP, the parts of it they used and whether any of it was on a phone
# (PLAN.md H.2), for the admin Usage page (UsageReport). No times, addresses, URLs or records
# viewed. Written by RecordsActivity, at most once per area per day.
class ActivityDay < ApplicationRecord
  belongs_to :user

  # The parts of WISP, by controller (or controller#action where one controller serves several).
  # A controller not listed (weather polling, impersonation, admin) isn't recorded. Any CSV
  # download is "reports", whichever controller sends it.
  AREAS = {
    "dashboard" => "dashboard",
    "daily_entries" => "daily",
    "fields" => "field", "field_days" => "field", "field_outlines" => "field",
    "plantings" => "planting", "canopy_cuttings" => "planting",
    "pivots" => "system", "pivot_irrigations" => "system",
    "map" => "map",
    "weather_zones" => "weather",
    "setup" => "setup", "quick_setups" => "setup", "season_copies" => "setup", "outline_imports" => "setup",
    "farms" => "setup", "pivot_groups" => "setup",
    "alerts" => "alerts",
    "season_reports" => "reports",
    "groups" => "operation", "memberships" => "operation", "current_groups" => "operation",
    "settings" => "settings",
    "pages#about" => "about"
  }.freeze

  # Every area, in the order the Usage page lists them
  AREA_NAMES = %w[dashboard daily field planting system map weather setup alerts reports operation settings about].freeze

  def self.area_for(controller_path, action_name, csv: false)
    return "reports" if csv && AREAS.key?(controller_path)

    AREAS["#{controller_path}##{action_name}"] || AREAS[controller_path]
  end

  # Adds the area (and phone) to the user's row for the day, making it if needed
  def self.record(user, date:, area:, phone: false)
    sql = sanitize_sql_array([<<~SQL, user.id, date, "{#{area}}", phone])
      INSERT INTO activity_days (user_id, date, areas, phone) VALUES (?, ?, ?::varchar[], ?)
      ON CONFLICT (user_id, date) DO UPDATE SET
        areas = ARRAY(SELECT DISTINCT unnest(activity_days.areas || EXCLUDED.areas) ORDER BY 1),
        phone = activity_days.phone OR EXCLUDED.phone
    SQL
    connection.exec_insert(sql, "ActivityDay Record")
  end
end
