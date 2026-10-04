class FieldsController < AuthenticatedController
  before_action :require_owner, only: :destroy

  FORECAST_DAYS = Weather::Fetcher::FORECAST_DAYS

  # The field status page (PLAN.md §11): one planting's season with its summary, daily grid, chart
  # and weather. ?planting_id= picks the season; the default is today's planting, else the latest.
  def show
    field = Current.group.fields.includes(:soil_type, :field_groups, pivot: [:farm, :weather_cell],
      plantings: [:plant, :canopy_observations]).find(params[:id])
    planting = field.plantings.find { |p| p.id == params[:planting_id].to_i } || default_planting(field)
    WeatherCell.keep_current([field.pivot.weather_cell_id])

    render inertia: "Fields/Show", props: {
      field: FieldSerializer.new(field).to_h,
      pivot: {id: field.pivot.id, name: field.pivot.name, pump_capacity_gpm: field.pivot.pump_capacity_gpm},
      farm: {id: field.pivot.farm.id, name: field.pivot.farm.name},
      field_groups: field.field_groups.map { |group| {id: group.id, name: group.name} },
      planting: planting && PlantingSerializer.new(planting).to_h,
      **(planting ? season_props(field, planting) : {summary: nil, days: [], weather: []})
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
    params.expect(field: [:pivot_id, :name, :area_acres, :soil_type_id, :field_capacity, :perm_wilting_pt, :notes])
  end

  def default_planting(field)
    today = Date.current
    field.planting_on(today) || field.plantings.select { |p| p.season_start <= today }.max_by(&:season_start) ||
      field.plantings.min_by(&:season_start)
  end

  def season_props(field, planting)
    status = PlantingStatus.new(planting)
    dates = planting.season_range
    attribute = (planting.et_method == "lai") ? :lai : :pct_cover
    pivot_inches = field.pivot.pivot_irrigations.where(date: dates).select { |irrigation| irrigation.applies_to?(field) }
      .to_h { |irrigation| [irrigation.date, irrigation.applied_inches] }
    weather_dates = planting.season_start..[planting.end_date, Date.current + FORECAST_DAYS].min

    {
      summary: PlantingSummarySerializer.new(status).to_h,
      days: FieldDaySerializer.new(status.days, params: {
        entries: field.field_entries.where(date: dates).index_by(&:date),
        observations: planting.canopy_observations.to_h { |obs| [obs.date, obs[attribute]] }.compact,
        pivot_inches:
      }).to_h,
      weather: WeatherPanelDaySerializer.new(
        WeatherPanel.new(field.pivot.weather_cell, weather_dates, emergence_date: planting.emergence_date).days
      ).to_h
    }
  end
end
