# Weather units as stored: inches, °F, mph, kPa, percent, MJ/m², and soil moisture in m³/m³.
# corrections: the labels of the corrections the day went through (Weather::Corrections).
class WeatherPanelDaySerializer < ApplicationSerializer
  attributes :date, :forecast, :gdd, :gdd_since_emergence, :corrections, *WeatherPanel::COLUMNS

  typelize date: :string, forecast: :boolean, gdd: "number | null", gdd_since_emergence: "number | null",
    corrections: "string[]",
    **WeatherPanel::COLUMNS.index_with { "number | null" }
end
