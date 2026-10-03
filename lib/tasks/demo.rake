namespace :demo do
  desc "Create (or rebuild) a demo account with realistic farms: bin/rails demo:seed [EMAIL=… PASSWORD=… YEAR=…]"
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
end
