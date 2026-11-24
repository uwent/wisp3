# The browser tests (bin/e2e) run on a fixed day, so they pass whatever the real date: the demo's
# season, its weather and "today" would otherwise move with the calendar. With E2E_NOW set
# (e2e/clock.json; the test environment only), this process's clock starts at that time and runs on,
# for the seed and the server alike. An offset rather than Rails' travel_to, which stops the clock:
# pages wait on time passing (limits, cooldowns, a sign-up sent too fast to be a person's).
if Rails.env.test? && ENV["E2E_NOW"].present?
  offset = Time.iso8601(ENV["E2E_NOW"]) - Time.now

  Time.singleton_class.prepend(Module.new do
    define_method(:now) { |*args, **options| super(*args, **options) + offset }
  end)
  # Date.today and DateTime.now read the system clock themselves
  Date.singleton_class.prepend(Module.new do
    define_method(:today) { |*| Time.now.to_date }
  end)
  DateTime.singleton_class.prepend(Module.new do
    define_method(:now) { |*| Time.now.to_datetime }
  end)
end
