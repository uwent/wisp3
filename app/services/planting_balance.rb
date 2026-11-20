# Runs the water balance for a planting over its season, from the database and weather:
# Canopy + DailyInputs + WaterBalance::Params → WaterBalance.run. Weather defaults to the stored
# days for the planting's weather cell (its pivot's, kept for the season, G.9); pass weather: {date => {et0:, precip:}} to override, and
# records: (DailyInputs.preload) to skip querying the field's entries. today: where the projection
# starts (DailyInputs). canopy_through: leaves out canopy readings after that date (Canopy.for).
# temperatures: the cell's CellTemperatures for a canopy curve in degree days (Canopy.for; loaded
# if needed and not given).
class PlantingBalance
  Day = Data.define(:inputs, :canopy, :result)

  def initialize(planting, weather: nil, records: nil, today: Current.today, canopy_through: nil, temperatures: nil)
    @planting, @weather, @records, @today, @canopy_through = planting, weather, records, today, canopy_through
    @temperatures = temperatures
  end

  def params = @params ||= WaterBalance::Params.for(@planting)

  def canopy = @canopy ||= Canopy.for(@planting, through: @canopy_through, temperatures: @temperatures)

  # One Day per date from season start through `through` (default: end_date)
  def days(through: @planting.end_date)
    dates = (@planting.season_start..[through, @planting.end_date].min).to_a
    weather = @weather || WeatherDay.balance_inputs(@planting.weather_cell, dates)
    inputs = DailyInputs.new(@planting.field, dates, weather:, records: @records, today: @today,
      planting: @planting).days
    canopies = dates.map { |date| canopy.on(date) }

    balance_days = inputs.zip(canopies).map do |day, canopy_value|
      WaterBalance::Day.new(date: day.date, et0: day.et0, rain: day.rain, irrigation: day.irrigation,
        soil_moisture_pct: day.soil_moisture_pct, canopy: canopy_value,
        wind_mph: day.wind_mph, rh_min_pct: day.rh_min_pct)
    end
    results = WaterBalance.run(params, balance_days)
    inputs.zip(canopies, results).map { |input, canopy_value, result| Day.new(input, canopy_value, result) }
  end
end
