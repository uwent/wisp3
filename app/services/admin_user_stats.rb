# What each account has set up, for the admin users table and its CSV (AdminUsersCsv): farms,
# irrigation systems, fields and plantings (this season's and all) over every group the user belongs
# to, the bounding box of those systems' locations, and when the user was last active
# (ActivityDay). A few grouped queries for every account at once, not one per user. A group shared by
# several users counts for each of them.
class AdminUserStats
  Stats = Struct.new(:groups, :owned_groups, :farms, :systems, :fields, :plantings_season, :plantings,
    :south, :west, :north, :east, :last_active_on, :days_active_season)

  EMPTY = {groups: 0, owned_groups: 0, farms: 0, systems: 0, fields: 0, plantings_season: 0, plantings: 0}.freeze

  attr_reader :year

  def initialize(year: Current.today.year)
    @year = year
  end

  # Stats for the user (empty for one with nothing set up)
  def [](user_id) = by_user.fetch(user_id) { Stats.new(**EMPTY) }

  private

  def by_user
    @by_user ||= begin
      stats = Membership.pluck(:user_id, :group_id, :owner).each_with_object({}) do |(user_id, group_id, owner), all|
        totals = all[user_id] ||= Stats.new(**EMPTY)
        totals.groups += 1
        totals.owned_groups += 1 if owner
        %i[farms systems fields plantings_season plantings].each do |kind|
          totals[kind] += counts[kind].fetch(group_id, 0)
        end
        extend_bounds(totals, bounds[group_id])
      end
      activity.each do |user_id, (last, days)|
        totals = stats[user_id] ||= Stats.new(**EMPTY)
        totals.last_active_on = last
        totals.days_active_season = days
      end
      stats
    end
  end

  def counts
    @counts ||= {
      farms: Farm.group(:group_id).count,
      systems: systems.count,
      fields: Field.joins(system: :farm).group("farms.group_id").count,
      plantings: plantings.count,
      plantings_season: plantings.where(season_start: Date.new(year, 1, 1)..Date.new(year, 12, 31)).count
    }
  end

  def systems = IrrigationSystem.joins(:farm).group("farms.group_id")

  def plantings = Planting.joins(system: :farm).group("farms.group_id")

  # {group_id => [south, west, north, east]} of its systems' locations
  def bounds
    @bounds ||= systems.pluck("farms.group_id", Arel.sql("MIN(irrigation_systems.latitude)"), Arel.sql("MIN(irrigation_systems.longitude)"),
      Arel.sql("MAX(irrigation_systems.latitude)"), Arel.sql("MAX(irrigation_systems.longitude)"))
      .to_h { |group_id, *box| [group_id, box] }
  end

  def extend_bounds(totals, box)
    return unless box

    south, west, north, east = box
    totals.south = [totals.south, south].compact.min
    totals.west = [totals.west, west].compact.min
    totals.north = [totals.north, north].compact.max
    totals.east = [totals.east, east].compact.max
  end

  # {user_id => [last day active, days active in the year]}
  def activity
    in_year = Arel.sql(ActivityDay.sanitize_sql_array(["COUNT(*) FILTER (WHERE date BETWEEN ? AND ?)",
      Date.new(year, 1, 1), Date.new(year, 12, 31)]))
    ActivityDay.group(:user_id).pluck(:user_id, Arel.sql("MAX(date)"), in_year)
      .to_h { |user_id, last, days| [user_id, [last, days]] }
  end
end
