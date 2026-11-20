require "rails_helper"

RSpec.describe Weather::Normals do
  let(:cell) { WeatherCell.for(44.12, -89.53) }
  let(:fixture) { file_fixture("open_meteo/archive_daily_two_years.json").read }

  it "fetches the archive's daily highs and lows once and stores a normal for every day of a leap year (recorded response)" do
    request = stub_request(:get, "https://archive-api.open-meteo.com/v1/archive")
      .with(query: hash_including(latitude: "44.112477", longitude: "-89.589041", daily: "temperature_2m_max,temperature_2m_min",
        models: "era5_seamless", timezone: "auto", start_date: "2024-01-01", end_date: "2025-12-31"))
      .to_return(body: fixture)

    stored = described_class.new(client: Weather::OpenMeteo.new(api_key: nil, sleeper: ->(_) {}))
      .fetch(cell, today: Date.new(2026, 11, 20), years: 2)
    expect(request).to have_been_made.once
    expect(stored).to eq(366)
    expect(cell.weather_normals.pluck(:day_of_year)).to match_array(1..366)
    expect(cell.weather_normals.first).to have_attributes(first_year: 2024, last_year: 2025, model: "era5_seamless")
    expect(cell).to be_normals

    january, july = [1, 196].map { |day| cell.weather_normals.find_by(day_of_year: day) } # Jan 1, Jul 14
    expect(july.tmax_f).to be_between(75, 90)
    expect(july.tmin_f).to be_between(55, 68)
    expect(january.tmax_f).to be < 35
    expect(july.tmax_f).to be > july.tmin_f
  end

  it "averages each day over the years, then over the WINDOW days around it, across the new year" do
    dates = (Date.new(2023, 1, 1)..Date.new(2024, 12, 31)).to_a
    # Highs of 10 °C in 2023 and 20 °C in 2024, except 40 °C on Jan 1, 2024; lows 0 °C
    highs = dates.map { |date| (date.year == 2023) ? 10.0 : 20.0 }
    highs[dates.index(Date.new(2024, 1, 1))] = 40.0
    normals = described_class.compute(dates, highs, dates.map { 0.0 })

    expect(normals.keys).to eq((1..366).to_a)
    expect(normals[183]).to eq([59.0, 32.0]) # mid-year: (10 + 20) / 2 = 15 °C
    # Jan 1's two years average 25 °C, over the 15 days around it (Dec 25 to Jan 8): 15.67 °C
    expect(normals[1]).to eq([60.2, 32.0])
    expect(normals[366]).to eq([60.2, 32.0]) # Dec 31 sees Jan 1 too
    # Feb 29 is only in 2024 (20 °C), so it and the days around it come out at 15.33 °C, no step
    expect(normals[60]).to eq([59.6, 32.0])
    expect(normals[59]).to eq(normals[60])
  end

  it "leaves out a day missing its high or low" do
    dates = [Date.new(2024, 7, 1), Date.new(2025, 7, 1)]
    expect(described_class.compute(dates, [30.0, 20.0], [10.0, nil])[183]).to eq([86.0, 50.0])
  end

  it "says so when the archive has no temperatures" do
    dates = [Date.new(2025, 1, 1)]
    expect { described_class.compute(dates, [nil], [nil]) }.to raise_error(Weather::Error, /no temperatures/)
  end

  it "counts days of the year as in a leap year" do
    expect(WeatherNormal.day_of_year(Date.new(2026, 2, 28))).to eq(59)
    expect(WeatherNormal.day_of_year(Date.new(2024, 2, 29))).to eq(60)
    expect(WeatherNormal.day_of_year(Date.new(2026, 3, 1))).to eq(61)
    expect(WeatherNormal.day_of_year(Date.new(2026, 12, 31))).to eq(366)
  end
end
