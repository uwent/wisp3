# How growers use WISP in a season (PLAN.md H.3), for the admin Usage page: accounts, the onboarding
# funnel, weekly activity (ActivityDay) and entries, the parts of WISP used, and how operations are
# set up. Admins, the example farm and example.com addresses (the demo account) are left out. A
# season is a calendar year; its weeks run March through November. Entries count from their
# created_at: the first time a day was entered, not later edits.
class UsageReport
  # Days active in a season that make an account a regular user, the funnel's last step
  REGULAR_DAYS = 10
  ZONE = "America/Chicago"

  attr_reader :year, :today

  def initialize(year, today: Date.current)
    @year = year
    @today = today
  end

  def props
    {
      year:,
      years:,
      tiles:,
      funnel:,
      weeks: weeks.map(&:iso8601),
      weekly_active: weekly_active(year),
      previous_weekly_active: previous_season? ? weekly_active(year - 1) : nil,
      weekly_entries:,
      areas:,
      phone_share:,
      setup:,
      return_rate:
    }
  end

  private

  def season = Date.new(year, 1, 1)..Date.new(year, 12, 31)

  def season_times = season.first.in_time_zone..season.last.end_of_day.in_time_zone

  # Mondays from the week of March 1 to the week of November 30
  def weeks
    @weeks ||= (Date.new(year, 3, 1).beginning_of_week..Date.new(year, 11, 30)).step(7).to_a
  end

  def years
    first = [users.minimum(:created_at)&.year, ActivityDay.minimum(:date)&.year, today.year].compact.min
    (first..today.year).to_a.reverse
  end

  # Accounts counted: not admins or the demo account
  def users = User.where(admin: false).where.not("email ILIKE ?", "%@example.com")

  def activity = ActivityDay.where(user_id: users.select(:id))

  # Operations with a counted member (so not the example farm, which has none, or the demo account's)
  def groups = Group.where(id: Membership.where(user_id: users.select(:id)).select(:group_id))

  def farms = Farm.where(group_id: groups.select(:id))

  def pivots = Pivot.where(farm_id: farms.select(:id))

  def fields = Field.where(pivot_id: pivots.select(:id))

  def plantings = Planting.where(pivot_id: pivots.select(:id))

  def season_plantings = plantings.where(season_start: season)

  def tiles
    {
      accounts: users.where.not(confirmed_at: nil).count,
      new_accounts: users.where(created_at: season_times).count,
      active_week: active_since(today - 6),
      active_month: active_since(today - 29),
      operations_entering: entry_group_ids.size
    }
  end

  def active_since(date) = activity.where(date: date..today).distinct.count(:user_id)

  # The groups with an entry made in the season, any kind
  def entry_group_ids
    @entry_group_ids ||= entry_scopes.values.flat_map { |scope, _| scope.distinct.pluck("farms.group_id") }.uniq
  end

  # Each kind of entry made in the season, joined to its farm: {kind => [scope, condition]}
  def entry_scopes
    @entry_scopes ||= begin
      field_entries = FieldEntry.joins(field: {pivot: :farm}).where(created_at: season_times, farms: {group_id: groups.select(:id)})
      planting_entries = PlantingEntry.joins(planting: {pivot: :farm}).where(created_at: season_times, farms: {group_id: groups.select(:id)})
      {
        rain: [field_entries.where.not(rain_in: nil)],
        irrigation: [
          field_entries.where.not(irrigation_in: nil),
          planting_entries.where.not(irrigation_in: nil),
          PivotIrrigation.joins(pivot: :farm).where(created_at: season_times, farms: {group_id: groups.select(:id)})
        ],
        soil_moisture: [field_entries.where.not(soil_moisture_pct: nil), planting_entries.where.not(soil_moisture_pct: nil)],
        canopy: [CanopyObservation.joins(planting: {pivot: :farm}).where(created_at: season_times, farms: {group_id: groups.select(:id)})]
      }
    end
  end

  # Accounts that signed up in the season, and how far each got
  def funnel
    signed_up = users.where(created_at: season_times)
    ids = signed_up.pluck(:id)
    confirmed = signed_up.where.not(confirmed_at: nil).pluck(:id)
    with_farm = member_ids(farms.distinct.pluck(:group_id), ids)
    with_planting = member_ids(Farm.joins(:pivots).where(pivots: {id: season_plantings.select(:pivot_id)}).distinct.pluck(:group_id), ids)
    with_entry = member_ids(entry_group_ids, ids)
    regular = ActivityDay.where(user_id: ids, date: season).group(:user_id).having("count(*) >= ?", REGULAR_DAYS).count.keys
    # Each step counts only accounts that made the steps before it
    steps = {signed_up: ids, confirmed:, farm: with_farm, planting: with_planting, entry: with_entry, regular:}
    reached = ids
    steps.map do |key, step_ids|
      reached &= step_ids
      {key: key.to_s, count: reached.size}
    end
  end

  def member_ids(group_ids, user_ids) = Membership.where(group_id: group_ids, user_id: user_ids).distinct.pluck(:user_id)

  # Accounts active each week of the season, in the order of weeks
  def weekly_active(of_year)
    shift = year - of_year
    counts = activity.where(date: Date.new(of_year, 1, 1)..Date.new(of_year, 12, 31))
      .group(Arel.sql("date_trunc('week', date)::date")).distinct.count(:user_id).transform_keys(&:to_date)
    # Last season's weeks lined up with this one's, 52 weeks apart
    weeks.map { |monday| counts.fetch(monday - (shift * 364).days, 0) }
  end

  def previous_season? = activity.where(date: Date.new(year - 1, 1, 1)..Date.new(year - 1, 12, 31)).exists?

  # Entries made each week of the season, by kind
  def weekly_entries
    entry_scopes.transform_values do |scopes|
      totals = Hash.new(0)
      scopes.each do |scope|
        week = Arel.sql("date_trunc('week', #{scope.table_name}.created_at AT TIME ZONE 'UTC' AT TIME ZONE '#{ZONE}')::date")
        scope.group(week).count.each { |monday, count| totals[monday.to_date] += count }
      end
      weeks.map { |monday| totals[monday] }
    end
  end

  # Accounts that used each part of WISP, in the season and in the last 30 days
  def areas
    season_areas = area_counts(activity.where(date: season))
    month_areas = area_counts(activity.where(date: (today - 29)..today))
    {
      season_active: activity.where(date: season).distinct.count(:user_id),
      month_active: active_since(today - 29),
      counts: ActivityDay::AREA_NAMES.map do |area|
        {area:, season: season_areas.fetch(area, 0), month: month_areas.fetch(area, 0)}
      end
    }
  end

  def area_counts(scope)
    scope.from("activity_days, unnest(activity_days.areas) AS area").group("area").distinct.count(:user_id)
  end

  # The share of active days in the season with any use on a phone, or nil before any
  def phone_share
    days = activity.where(date: season)
    total = days.count
    total.zero? ? nil : (days.where(phone: true).count.to_f / total).round(3)
  end

  def setup
    # Operations with a farm (every account starts with an empty one of its own)
    member_counts = Membership.where(group_id: farms.select(:group_id)).group(:group_id).count
    confirmed = users.where.not(confirmed_at: nil)
    {
      operations: member_counts.size,
      shared_operations: member_counts.count { |_, count| count > 1 },
      farms: farms.count,
      systems: pivots.group(:kind).count.map { |kind, count| {name: Pivot::KIND_NAMES.fetch(kind, kind), count:} }
        .sort_by { |row| -row[:count] },
      fields: fields.count,
      outlined_fields: fields.where.not(boundary: nil).count,
      plantings: season_plantings.count,
      plots: season_plantings.where(partial: true).count,
      crops: season_plantings.joins(:plant).group("plants.name").count.map { |name, count| {name:, count:} }
        .sort_by { |row| [-row[:count], row[:name]] },
      units: confirmed.group(:unit_system).count,
      digests: confirmed.group(:digest_frequency).count
    }
  end

  # Accounts active last season, and how many of them came back this one, or nil before there's a
  # last season to compare
  def return_rate
    before = activity.where(date: Date.new(year - 1, 1, 1)..Date.new(year - 1, 12, 31)).distinct.pluck(:user_id)
    return if before.empty?

    {previous_year: year - 1, active: before.size, returned: activity.where(date: season, user_id: before).distinct.count(:user_id)}
  end
end
