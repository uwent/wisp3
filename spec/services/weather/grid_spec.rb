require "rails_helper"

RSpec.describe Weather::Grid do
  # Cell centers Open-Meteo returned for models=ecmwf_ifs at these points (2026-10-03)
  {
    [44.12, -89.53] => [44.112476, -89.58905], # Hancock, WI
    [44.0773, -89.6] => [44.04218, -89.58966], # the next ring south
    [36.7, -119.8] => [36.731106, -119.76378], # Fresno, CA
    [50.4, -104.6] => [50.36907, -104.57745], # Regina, SK
    [30.27, -97.74] => [30.263618, -97.69321], # Austin, TX
    [46.8, -71.2] => [46.78383, -71.24393] # Québec
  }.each do |(lat, lng), (cell_lat, cell_lng)|
    it "puts #{lat}, #{lng} in Open-Meteo's cell at #{cell_lat}, #{cell_lng}" do
      cell = described_class.cell_for(lat, lng)
      expect(cell.latitude).to be_within(1e-4).of(cell_lat)
      expect(cell.longitude).to be_within(1e-4).of(cell_lng)
    end
  end

  it "returns a cell containing the point, whose own center maps back to it" do
    rng = Random.new(3)
    50.times do
      lat, lng = rng.rand(18.0..84.0), rng.rand(-180.0..-52.0)
      cell = described_class.cell_for(lat, lng)
      expect(lat).to be_between(cell.lat_south, cell.lat_north)
      expect((lng - cell.longitude + 180) % 360 - 180).to be_between(cell.lng_west - cell.longitude, cell.lng_east - cell.longitude)
      expect(described_class.cell_for(cell.latitude, cell.longitude)).to eq(cell)
    end
  end

  it "has 20 points on the polar rings and 5136 at the equator" do
    polar = described_class.cell_for(89.99, 10)
    expect(polar.lng_east - polar.lng_west).to be_within(1e-9).of(18.0)
    equator = described_class.cell_for(0.01, 10)
    expect(equator.lng_east - equator.lng_west).to be_within(1e-9).of(360.0 / (20 + 4 * 1279))
  end
end
