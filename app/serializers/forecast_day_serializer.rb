# A day of the week ahead (ForecastDays), values as stored: inches, °F, mph, percent. weather_code is
# the day's most severe WMO code (lib/forecast.ts words it); precip_chance the ensemble's share of
# members with measurable precipitation.
class ForecastDaySerializer < ApplicationSerializer
  attributes :date, *ForecastDays::COLUMNS, :precip_chance

  typelize date: :string, precip_chance: "number | null", **ForecastDays::COLUMNS.index_with { "number | null" }
end
