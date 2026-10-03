require "rails_helper"

RSpec.describe Weather::OpenMeteo do
  let(:fixture) { file_fixture("open_meteo/forecast_two_locations.json").read }
  let(:client) { described_class.new(api_key: nil, sleeper: ->(_) {}) }
  let(:locations) { [[44.112477, -89.589041], [36.731106, -119.76378]] }
  let(:variables) { %w[temperature_2m et0_fao_evapotranspiration precipitation wind_direction_10m] }

  def fetch(client = self.client)
    client.hourly(locations, endpoint: :forecast, model: "best_match", variables:,
      start_date: Date.new(2026, 10, 1), end_date: Date.new(2026, 10, 2))
  end

  it "requests every location at once from the free host and parses each (recorded response)" do
    request = stub_request(:get, "https://api.open-meteo.com/v1/forecast")
      .with(query: hash_including(latitude: "44.112477,36.731106", longitude: "-89.589041,-119.76378",
        hourly: variables.join(","), models: "best_match", timezone: "auto", start_date: "2026-10-01", end_date: "2026-10-02"))
      .to_return(body: fixture)

    hancock, fresno = fetch
    expect(request).to have_been_made.once
    expect(hancock).to have_attributes(timezone: "America/Chicago", times: have_attributes(size: 48))
    expect(fresno.timezone).to eq("America/Los_Angeles")
    expect(hancock.values["et0_fao_evapotranspiration"].compact.size).to eq(48)
  end

  it "parses a single-location response (an object, not a list)" do
    stub_request(:get, /api.open-meteo.com/).to_return(body: file_fixture("open_meteo/soil_one_location.json").read)
    result = client.hourly([locations.first], endpoint: :forecast, model: "ecmwf_ifs",
      variables: %w[soil_temperature_0_to_7cm soil_moisture_0_to_7cm], past_days: 1, forecast_days: 1)
    expect(result.size).to eq(1)
    expect(result.first.values["soil_moisture_0_to_7cm"].compact).not_to be_empty
  end

  it "uses the customer host and sends the key when there is one" do
    keyed = described_class.new(api_key: "secret", sleeper: ->(_) {})
    request = stub_request(:get, %r{\Ahttps://customer-api\.open-meteo\.com/v1/forecast\?.*apikey=secret}).to_return(body: fixture)
    fetch(keyed)
    expect(request).to have_been_made
    expect(keyed.mode).to eq(:customer)
    expect(client.mode).to eq(:free)
  end

  it "retries 429s and server errors, then gives up with a TransientError" do
    stub_request(:get, /open-meteo/).to_return({status: 429, body: '{"reason":"Too many"}'}, {status: 503}, {body: fixture})
    expect(fetch.size).to eq(2)

    stub_request(:get, /open-meteo/).to_return(status: 502)
    expect { fetch }.to raise_error(Weather::TransientError, /502/)
  end

  it "raises a plain Error for a bad request, with Open-Meteo's reason" do
    stub_request(:get, /open-meteo/).to_return(status: 400, body: '{"error":true,"reason":"Invalid model"}')
    expect { fetch }.to raise_error(Weather::Error, /Invalid model/)
  end

  it "counts usage the way Open-Meteo does" do
    stub_request(:get, /open-meteo/).to_return(body: fixture)
    fetch
    # 2 locations × max(1, 4 variables / 10 × 2 days / 14)
    expect(Weather::RateLimiter.new.used(:minute)).to eq(2.0)
  end
end

RSpec.describe Weather::RateLimiter do
  it "weighs requests by locations, variables and days" do
    expect(described_class.weight(locations: 3, variables: 17, days: 23)).to be_within(1e-9).of(3 * 1.7 * 23 / 14.0)
    expect(described_class.weight(locations: 1, variables: 5, days: 7)).to eq(1.0)
  end

  it "waits out the minute when it's full, and raises when the hour is" do
    waits = []
    limiter = described_class.new(limits: {minute: 10, hour: 15}, sleeper: ->(seconds) { waits << seconds })
    limiter.acquire!(8)
    limiter.acquire!(4)
    expect(waits.size).to eq(1)
    expect { limiter.acquire!(5) }.to raise_error(Weather::RateLimited) { |e| expect(e.retry_in).to be_between(1, 3600) }
  end

  it "doesn't limit without limits (customer keys)" do
    limiter = described_class.new(limits: nil)
    expect { 5.times { limiter.acquire!(10_000) } }.not_to raise_error
  end
end
