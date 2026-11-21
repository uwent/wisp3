# Every account as one CSV, from the admin users page: who it is, when it signed up and was last
# active, its digest setting, and what it has set up (AdminUserStats), with the bounding box of its
# irrigation systems' locations. Frontmatter as WISP's other exports (CsvExport).
class AdminUsersCsv
  include CsvExport

  HEADER = ["ID", "Email", "First name", "Last name", "Admin", "Created", "Confirmed", "Last signed in",
    "Last active", "Days active (YEAR)", "Daily digest", "Operations", "Operations owned", "Farms",
    "Irrigation systems", "Fields", "Plantings (YEAR)", "Plantings (all seasons)",
    "South latitude", "West longitude", "North latitude", "East longitude"].freeze

  def initialize(users, stats, exported_by: nil, about_url: nil)
    @users, @stats, @exported_by, @about_url = users, stats, exported_by, about_url
  end

  def to_csv
    generate do |csv|
      frontmatter(csv, "WISP accounts", details, exported_by: @exported_by, about_url: @about_url,
        units: "latitude and longitude in decimal degrees (WGS 84); dates in Central time")
      csv << HEADER.map { |label| label.sub("YEAR", @stats.year.to_s) }
      @users.each { |user| csv << row(user, @stats[user.id]) }
    end
  end

  private

  def details
    {
      "Accounts" => @users.size.to_s,
      "Counts" => "farms, irrigation systems, fields and plantings over every operation the account belongs to, " \
        "so an operation shared by several accounts counts for each of them",
      "Last active" => "the last day the account used WISP's pages (recorded since WISP 3's launch); " \
        "last signed in can be much older, as a remembered session stays signed in",
      "Bounding box" => "of the account's irrigation systems' locations (their pins, not field outlines); " \
        "blank without any"
    }
  end

  def row(user, stats)
    [
      user.id, text(user.email), text(user.first_name), text(user.last_name), yes_no(user.admin?),
      date(user.created_at), user.confirmed_at && date(user.confirmed_at), user.current_sign_in_at && date(user.current_sign_in_at),
      stats.last_active_on&.iso8601, stats.days_active_season || 0, user.digest_frequency,
      stats.groups, stats.owned_groups, stats.farms, stats.pivots, stats.fields, stats.plantings_season, stats.plantings,
      num(stats.south), num(stats.west), num(stats.north), num(stats.east)
    ]
  end

  def date(time) = time.in_time_zone.to_date.iso8601

  def yes_no(value) = value ? "yes" : "no"
end
