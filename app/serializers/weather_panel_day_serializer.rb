# Weather units as stored: inches, °F, mph, kPa, percent, and soil moisture in m³/m³
class WeatherPanelDaySerializer < ApplicationSerializer
  attributes :date, :forecast, :gdd, :gdd_since_emergence, *WeatherPanel::COLUMNS

  typelize date: :string, forecast: :boolean, gdd: "number | null", gdd_since_emergence: :number,
    **WeatherPanel::COLUMNS.index_with { "number | null" }
end
