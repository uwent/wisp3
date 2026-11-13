class FieldsController < AuthenticatedController
  before_action :require_owner, only: :destroy

  # The field page (PLAN.md Phase 8 G.11): the land rather than one crop on it. Its season's
  # plantings on a timeline, a status card for each, and the field's own rain and irrigation, which
  # every planting on it shares (no balance: that's each planting's page). ?year= picks the season.
  # ?planting_id= (links from before plantings had their own pages) goes to that planting's page.
  def show
    field = Current.group.fields.includes(:soil_type, pivot: [:farm, :weather_cell],
      plantings: [:plant, :canopy_observations, :canopy_cuttings, :soil_type, :weather_cell]).find(params[:id])
    if (planting = field.plantings.find { |p| p.id == params[:planting_id].to_i })
      return redirect_to planting_path(planting, request.query_parameters.slice("as_of"))
    end

    today = Date.current
    year = params.fetch(:year, today.year).to_i
    plantings = field.plantings.select { |p| p.season_year == year }
    WeatherCell.keep_current([field.pivot.weather_cell_id])
    weather_updating = WeatherCell.updating_ids([field.pivot.weather_cell_id]).any?

    render inertia: "Fields/Show", props: {
      **FieldHeaderProps.for(field),
      year:,
      years: (field.plantings.map(&:season_year) + [today.year, year]).uniq.sort,
      weather_updating:,
      **WeatherZone.page_props(Current.group, field.pivot.weather_cell, forecast: year == today.year),
      plantings: summaries(field, plantings, today),
      days: field_days(field, year, plantings, today),
      plants: PlantSerializer.new(Plant.order(:name)).to_h,
      soil_types: SoilTypeSerializer.new(SoilType.order(:field_capacity, :perm_wilting_pt)).to_h,
      generic_curves: GenericCurveSerializer.all
    }
  end

  def create
    field = Current.group.pivots.find(field_params[:pivot_id]).fields.build(field_params)
    # Back to Setup as it was (its season, or quick setup's next steps)
    if field.save
      redirect_back_or_to setup_path, notice: "Added #{field.name}"
    else
      redirect_with_errors(request.referer || setup_path, field)
    end
  end

  def update
    field = Current.group.fields.find(params[:id])
    field.pivot = Current.group.pivots.find(field_params[:pivot_id]) if field_params[:pivot_id]
    if field.update(field_params.except(:pivot_id))
      redirect_back_or_to setup_path, notice: "Saved #{field.name}"
    else
      redirect_with_errors(request.referer || setup_path, field)
    end
  end

  def destroy
    field = Current.group.fields.find(params[:id])
    field.destroy!
    redirect_to setup_path, notice: "Deleted #{field.name}"
  end

  private

  def field_params
    params.expect(field: [:pivot_id, :name, :area_acres, :soil_type_id, :field_capacity, :perm_wilting_pt, :notes,
      :use_model_precip, :boundary])
  end

  # Each planting of the season with its status today (PlantingSummarySerializer), sharing the
  # field's records
  def summaries(field, plantings, today)
    return [] if plantings.empty?
    dates = plantings.map(&:season_start).min..[plantings.map(&:end_date).max, today + PlantingStatus::HORIZON].min
    records = DailyInputs.preload([field], dates).fetch(field.id)
    weather = WeatherDay.balance_inputs_by_cell(plantings.map(&:weather_cell_id).uniq, dates)
    plantings.map do |planting|
      status = PlantingStatus.new(planting, today:, records:, weather: weather.fetch(planting.weather_cell_id, {}))
      PlantingSummarySerializer.new(status).to_h
    end
  end

  # The field's own rain and irrigation for each day of the season through today, newest first:
  # its plantings' span (Apr 1 – Nov 30 without any), with what each day resolves to for the field
  # as a whole (DailyInputs without a planting) and the notes entered on the field
  def field_days(field, year, plantings, today)
    from = plantings.map(&:season_start).min || Date.new(year, 4, 1)
    to = [plantings.map(&:end_date).max || Date.new(year, 11, 30), today].min
    return [] if to < from
    dates = (from..to).to_a
    inputs = DailyInputs.new(field, dates, weather: WeatherDay.balance_inputs(field.pivot.weather_cell, dates)).days
    entries = field.field_entries.where(date: from..to).index_by(&:date)
    inputs.reverse.map do |day|
      {date: day.date, rain: day.rain, rain_source: day.rain_source, rain_model: day.rain_model,
       irrigation: day.irrigation, irrigation_source: day.irrigation_source, notes: entries[day.date]&.notes}
    end
  end
end
