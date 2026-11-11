class FieldsController < AuthenticatedController
  before_action :require_owner, only: :destroy

  FORECAST_DAYS = Weather::Fetcher::FORECAST_DAYS

  # The field status page (PLAN.md §11): one planting's season with its summary, daily grid, chart
  # and weather. ?planting_id= picks the season; the default is today's planting, else the latest.
  # ?as_of= travels back to a day of that season before today (PLAN.md Phase 8 F): the page shows the
  # season as it stood then, read-only. A date outside the season, ahead or malformed redirects without it.
  def show
    field = Current.group.fields.includes(:soil_type, :field_groups, pivot: [:farm, :weather_cell],
      plantings: [:plant, :canopy_observations]).find(params[:id])
    past = requested_date&.then { |date| date if date < Date.current }
    planting = field.plantings.find { |p| p.id == params[:planting_id].to_i } ||
      default_planting(field, past || Date.current)
    as_of = past if planting&.season_range&.cover?(past)
    # An ?as_of= that can't be used leaves the URL, so it doesn't look like time travel
    return redirect_to field_path(field, request.query_parameters.except("as_of")) if params.key?(:as_of) && !as_of

    weather_updating = false
    unless as_of
      WeatherCell.keep_current([field.pivot.weather_cell_id])
      weather_updating = WeatherCell.updating_ids([field.pivot.weather_cell_id]).any?
    end

    render inertia: "Fields/Show", props: {
      field: FieldSerializer.new(field).to_h,
      pivot: {id: field.pivot.id, name: field.pivot.name, pump_capacity_gpm: field.pivot.pump_capacity_gpm},
      farm: {id: field.pivot.farm.id, name: field.pivot.farm.name},
      field_groups: field.field_groups.map { |group| {id: group.id, name: group.name} },
      weather_updating:,
      as_of:,
      travel_dates: planting && travel_dates(planting),
      planting: planting && PlantingSerializer.new(planting).to_h,
      **(planting ? season_props(field, planting, as_of) : {summary: nil, days: [], forecast_days: [], weather: []})
    }
  end

  def create
    field = Current.group.pivots.find(field_params[:pivot_id]).fields.build(field_params)
    if field.save
      redirect_to setup_path, notice: "Added #{field.name}"
    else
      redirect_with_errors setup_path, field
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
      :use_model_precip])
  end

  # The days of the season before today, which ?as_of= can pick ({from:, to:}), or nil if none
  def travel_dates(planting)
    to = [planting.end_date, Date.current - 1].min
    {from: planting.season_start, to:} if to >= planting.season_start
  end

  # ?as_of= as a date, or nil when it's missing or malformed
  def requested_date
    Date.iso8601(params[:as_of]) if params[:as_of].is_a?(String)
  rescue Date::Error
    nil
  end

  def default_planting(field, today)
    field.planting_on(today) || field.plantings.select { |p| p.season_start <= today }.max_by(&:season_start) ||
      field.plantings.min_by(&:season_start)
  end

  # as_of: time travelling, the days run to the end of the days that followed it, canopy readings
  # stop at it, and the weather panels end there
  def season_props(field, planting, as_of)
    status = PlantingStatus.new(planting, as_of:)
    dates = as_of ? planting.season_start..[as_of + PlantingStatus::HORIZON, planting.end_date].min : planting.season_range
    attribute = (planting.et_method == "lai") ? :lai : :pct_cover
    pivot_inches = field.pivot.pivot_irrigations.where(date: dates).select { |irrigation| irrigation.applies_to?(field) }
      .to_h { |irrigation| [irrigation.date, irrigation.applied_inches] }
    weather_dates = planting.season_start..(as_of || [planting.end_date, Date.current + FORECAST_DAYS].min)

    day_params = {
      entries: field.field_entries.where(date: dates).index_by(&:date),
      observations: planting.canopy_observations.select { |obs| dates.cover?(obs.date) && (!as_of || obs.date <= as_of) }
        .to_h { |obs| [obs.date, obs[attribute]] }.compact,
      pivot_inches:,
      canopy: status.canopy
    }

    {
      summary: PlantingSummarySerializer.new(status).to_h,
      days: FieldDaySerializer.new(status.days, params: day_params).to_h,
      # The projection's days, with planned irrigation (entries on future dates)
      forecast_days: FieldDaySerializer.new(status.forecast_days, params: day_params).to_h,
      weather: WeatherPanelDaySerializer.new(
        WeatherPanel.new(field.pivot.weather_cell, weather_dates, emergence_date: planting.emergence_date).days
      ).to_h
    }
  end
end
