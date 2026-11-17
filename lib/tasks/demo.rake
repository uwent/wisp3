namespace :demo do
  desc "Create (or rebuild) a demo account with realistic farms from db/demo/farms.yml: bin/rails demo:seed [EMAIL=… PASSWORD=… YEAR=…]"
  task seed: :environment do
    ReferenceData.load!
    result = DemoSeed.new(
      email: ENV.fetch("EMAIL", "demo@example.com"),
      password: ENV["PASSWORD"],
      year: Integer(ENV.fetch("YEAR", Date.current.year))
    ).run
    puts "Demo account #{result[:email]}#{" / #{result[:password]}" if result[:password]}: " \
      "#{result[:farms]} farms, #{result[:fields]} fields, #{result[:plantings]} plantings"
  end

  desc "Rebuild the public example farm (/example) from db/demo/farms.yml, as of July 20: bin/rails demo:example [YEAR=…]"
  task example: :environment do
    ReferenceData.load!
    group = DemoSeed.example!(year: Integer(ENV.fetch("YEAR", Date.current.year)))
    puts "Example farm as of #{group.example_as_of}: #{group.farms.count} farms, #{group.fields.count} fields"
  end

  desc "Write the demo account's farms, as edited in the app, back to db/demo/farms.yml: bin/rails demo:export [EMAIL=… YEAR=…]"
  task export: :environment do
    email = ENV.fetch("EMAIL", "demo@example.com")
    group = User.find_by!(email:).groups.find_by!(name: DemoSeed::GROUP_NAME)
    DemoSeed::FILE.write(DemoExport.new(group, year: Integer(ENV.fetch("YEAR", Date.current.year))).to_yaml)
    puts "Wrote #{DemoSeed::FILE.relative_path_from(Rails.root)} from #{email}"
  end
end
