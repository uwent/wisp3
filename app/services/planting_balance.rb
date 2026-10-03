# Runs the water balance for a planting over its season, from the database and weather:
# Canopy + DailyInputs + WaterBalance::Params → WaterBalance.run. Weather defaults to the stored
# days for the field's pivot's cell; pass weather: {date => {et0:, precip:}} to override.
class PlantingBalance
  Day = Data.define(:inputs, :canopy, :result)

  def initialize(planting, weather: nil)
    @planting, @weather = planting, weather
  end

  def params = @params ||= WaterBalance::Params.for(@planting)

  # One Day per date from season start through `through` (default: end_date)
  def days(through: @planting.end_date)
    dates = (@planting.season_start..[through, @planting.end_date].min).to_a
    canopy = Canopy.for(@planting)
    weather = @weather || WeatherDay.balance_inputs(@planting.field.pivot.weather_cell, dates)
    inputs = DailyInputs.new(@planting.field, dates, weather:).days
    canopies = dates.map { |date| canopy.on(date) }

    balance_days = inputs.zip(canopies).map do |day, canopy_value|
      WaterBalance::Day.new(date: day.date, et0: day.et0, rain: day.rain, irrigation: day.irrigation,
        soil_moisture_pct: day.soil_moisture_pct, canopy: canopy_value)
    end
    results = WaterBalance.run(params, balance_days)
    inputs.zip(canopies, results).map { |input, canopy_value, result| Day.new(input, canopy_value, result) }
  end
end
