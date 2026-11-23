namespace :usage do
  desc "Development only: sample accounts and activity for the admin Usage page, joined to the demo farms " \
    "(bin/rails usage:sample [YEAR=…]; CLEAR=1 removes them)"
  task sample: :environment do
    abort "usage:sample is for development only" unless Rails.env.development?

    domain = "usage.test"
    User.where("email LIKE ?", "%@#{domain}").find_each(&:destroy!)
    next puts "Removed the sample accounts" if ENV["CLEAR"]

    year = Integer(ENV.fetch("YEAR", Date.current.year))
    random = Random.new(2026)
    demo_groups = Group.joins(memberships: :user).where("users.email ILIKE ?", "%@example.com")
      .where(id: Farm.joins(systems: :plantings).select(:group_id)).distinct.to_a
    abort "Run bin/rails demo:seed first: the sample accounts join its farms" if demo_groups.empty?

    areas = ActivityDay::AREA_NAMES
    # How likely an active day touches each area: the dashboard nearly always, CSVs rarely
    weights = {"dashboard" => 0.9, "daily" => 0.5, "field" => 0.45, "planting" => 0.3, "system" => 0.2, "map" => 0.25,
               "weather" => 0.2, "setup" => 0.08, "alerts" => 0.04, "reports" => 0.03, "operation" => 0.02,
               "settings" => 0.03, "about" => 0.05}
    season = Date.new(year, 4, 15)..[Date.new(year, 12, 31), Date.current].min

    40.times do |i|
      signed_up = Time.zone.local(year, [2, 3, 3, 4, 4, 5, 6, 7].sample(random: random), random.rand(1..28), 9)
      confirmed = random.rand < 0.88
      user = User.new(first_name: "Sample", last_name: "Grower #{i + 1}", email: "grower#{i + 1}@#{domain}",
        password: SecureRandom.hex(16), created_at: signed_up, confirmed_at: confirmed ? signed_up + 1.hour : nil,
        unit_system: (random.rand < 0.1) ? "metric" : "imperial",
        digest_frequency: %w[never daily daily needed daily_all_year].sample(random: random))
      user.skip_confirmation_notification!
      user.save!
      next unless confirmed

      # Most get going on one of the demo operations; the rest stop at an empty one of their own
      engaged = random.rand < 0.7
      if engaged
        user.memberships.create!(group: demo_groups.sample(random: random), owner: false)
      else
        user.create_personal_group
      end

      # Days used: engaged growers through the season (more in July and August), the rest a few times
      start = [signed_up.to_date, season.first].max
      next if start > season.last

      chance = engaged ? random.rand(0.15..0.7) : 0.03
      rows = (start..season.last).filter_map do |date|
        peak = if date.month.in?([7, 8]) then 1.3
        elsif date > Date.new(year, 10, 15) then 0.15
        else 1.0
        end
        next unless random.rand < chance * peak

        used = areas.select { |area| random.rand < weights.fetch(area) }
        used = ["dashboard"] if used.empty?
        {user_id: user.id, date:, areas: used.sort, phone: random.rand < 0.35}
      end
      # Some were also around last season
      if engaged && random.rand < 0.5
        rows += (Date.new(year - 1, 5, 1)..Date.new(year - 1, 9, 30)).filter_map do |date|
          next unless random.rand < chance * 0.8

          {user_id: user.id, date:, areas: ["dashboard"], phone: false}
        end
      end
      ActivityDay.insert_all(rows) if rows.any?
    end

    # The demo's entries as if each was made on its day or a day or two after, not all at seeding
    [FieldEntry, PlantingEntry, CanopyObservation].each do |model|
      model.where("date <= ?", Date.current).find_each do |entry|
        made = entry.date.in_time_zone.change(hour: 7) + random.rand(0..2).days
        entry.update_columns(created_at: [made, Time.current].min)
      end
    end

    puts "40 sample accounts @#{domain}, #{ActivityDay.joins(:user).where("users.email LIKE ?", "%@#{domain}").count} active days"
  end
end
