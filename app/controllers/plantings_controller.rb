class PlantingsController < AuthenticatedController
  # A planting's page (PLAN.md §11; its own URL since G.11): its season with the summary, daily grid,
  # chart and the week ahead (its zone's panels are on the weather page, G.12). ?as_of= travels back
  # to a day of the season before today (PLAN.md Phase 8 F): the page shows the season as it stood
  # then, read-only. A date outside the season, ahead or malformed redirects without it.
  def show
    planting = Current.group.plantings.find(params[:id])
    field = Current.group.fields.includes(:soil_type, pivot: [:farm, :weather_cell],
      plantings: [:plant, :canopy_observations, :canopy_cuttings, :soil_type, :weather_cell]).find(planting.field_id)
    planting = field.plantings.find { |p| p.id == planting.id }
    past = requested_date&.then { |date| date if date < Date.current }
    as_of = past if planting.season_range.cover?(past)
    # An ?as_of= that can't be used leaves the URL, so it doesn't look like time travel
    return redirect_to planting_path(planting, request.query_parameters.except("as_of")) if params.key?(:as_of) && !as_of

    weather_updating = false
    unless as_of
      WeatherCell.keep_current([field.pivot.weather_cell_id])
      weather_updating = WeatherCell.updating_ids([field.pivot.weather_cell_id]).any?
    end

    render inertia: "Plantings/Show", props: {
      **FieldHeaderProps.for(field),
      weather_updating:,
      as_of:,
      travel_dates: travel_dates(planting),
      planting: PlantingSerializer.new(planting).to_h,
      # The zone the season ran on (G.9), and its week ahead while the season has days left
      **WeatherZone.page_props(Current.group, planting.weather_cell, forecast: !as_of && planting.end_date >= Date.current),
      **season_props(field, planting, as_of)
    }
  end

  # replace: end the whole-field planting this one overlaps the day before it starts ("Replace" on
  # the form), in the same transaction
  def create
    field = Current.group.fields.find(planting_params[:field_id])
    plant = Plant.find_by(id: planting_params[:plant_id])
    year = params.fetch(:year, Date.current.year).to_i
    given = planting_params.compact_blank.except(:field_id)
    defaults = plant ? Planting.defaults_for(plant, year) : {}
    # Without a harvest date, the crop's typical one after the emergence given (G.2)
    emergence = iso_date(given[:emergence_date])
    defaults[:end_date] = Planting.typical_end(plant, emergence, given[:canopy_curve_key]) if plant && emergence && !given[:end_date]
    planting = field.plantings.build(defaults.merge(given))
    saved = Planting.transaction do
      replace_overlapping(planting) if params[:replace].present?
      planting.save || raise(ActiveRecord::Rollback)
    end
    if saved
      redirect_back_or_to setup_path(year:), notice: "Added #{plant.name} on #{field.name}"
    else
      redirect_with_errors(request.referer || setup_path(year:), planting)
    end
  end

  def update
    planting = Current.group.plantings.find(params[:id])
    if planting.update(planting_params.except(:field_id))
      redirect_back_or_to setup_path(year: planting.season_year), notice: "Saved #{planting.plant.name} on #{planting.field.name}."
    else
      redirect_with_errors(request.referer || setup_path, planting)
    end
  end

  def destroy
    planting = Current.group.plantings.find(params[:id])
    planting.destroy!
    redirect_back_or_to setup_path(year: planting.season_year), notice: "Deleted #{planting.plant.name} on #{planting.field.name}"
  end

  # The season's daily balance as CSV (the legacy export's columns, plus where each value came from)
  def export
    planting = Current.group.plantings.includes(:plant, field: [:soil_type, {pivot: {farm: :group}}]).find(params[:id])
    filename = "wisp-#{planting.field.name.parameterize}-#{planting.season_year}.csv"
    csv = PlantingCsv.new(PlantingStatus.new(planting), exported_by: current_user, about_url:).to_csv
    send_data csv, filename:, type: "text/csv; charset=utf-8"
  end

  private

  # Ends the plantings on the field that the new one can't overlap (any, for a whole-field planting;
  # whole-field ones, for a plot) the day before it starts, when that's after their emergence; one
  # that starts the same day or later can't be replaced this way, and the overlap error stays
  def replace_overlapping(planting)
    return unless planting.season_start && planting.end_date
    clashing = planting.field.plantings.select { |other| other.overlaps?(planting) && !(planting.partial? && other.partial?) }
    clashing.each do |other|
      other.update!(end_date: planting.season_start - 1) if other.season_start < planting.season_start &&
        other.emergence_date < planting.season_start
    end
  end

  # The days of the season before today, which ?as_of= can pick ({from:, to:}), or nil if none
  def travel_dates(planting)
    to = [planting.end_date, Date.current - 1].min
    {from: planting.season_start, to:} if to >= planting.season_start
  end

  # ?as_of= as a date, or nil when it's missing or malformed
  def requested_date = iso_date(params[:as_of])

  def iso_date(value)
    Date.iso8601(value) if value.is_a?(String)
  rescue Date::Error
    nil
  end

  # as_of: time travelling, the days run to the end of the days that followed it, and canopy readings
  # stop at it
  def season_props(field, planting, as_of)
    status = PlantingStatus.new(planting, as_of:)
    dates = as_of ? planting.season_start..[as_of + PlantingStatus::HORIZON, planting.end_date].min : planting.season_range
    attribute = (planting.et_method == "lai") ? :lai : :pct_cover
    # The irrigation of the system the season ran on (G.14 part 7)
    pivot_inches = PivotIrrigation.where(pivot_id: planting.pivot_id, date: dates).select { |irrigation| irrigation.covers?(field.id) }
      .to_h { |irrigation| [irrigation.date, irrigation.applied_inches] }
    field_entries = field.field_entries.where(date: dates).index_by(&:date)

    day_params = {
      # Notes: a part-field planting's own (G.11), else the field's
      entries: planting.partial? ? planting.planting_entries.where(date: dates).index_by(&:date) : field_entries,
      observations: planting.canopy_observations.select { |obs| dates.cover?(obs.date) && (!as_of || obs.date <= as_of) }
        .to_h { |obs| [obs.date, obs[attribute]] }.compact,
      pivot_inches:,
      # A part-field planting's view of the field's irrigation, shown under its own (G.11)
      field_inches: planting.partial? ? field_entries.transform_values(&:irrigation_in).compact : {},
      canopy: status.canopy
    }

    {
      summary: PlantingSummarySerializer.new(status).to_h,
      days: FieldDaySerializer.new(status.days, params: day_params).to_h,
      # The projection's days, with planned irrigation (entries on future dates)
      forecast_days: FieldDaySerializer.new(status.forecast_days, params: day_params).to_h
    }
  end

  def planting_params
    params.expect(planting: [:field_id, :plant_id, :variety, :season_start, :emergence_date, :end_date, :vine_kill_date,
      :max_root_zone_depth, :mad_frac, :et_method, :canopy_interpolation, :target_ad_pct, :initial_moisture_pct, :notes,
      :soil_type_id, :field_capacity, :perm_wilting_pt, :area_acres,
      :partial, :plot_length_ft, :plot_width_ft, :own_soil, :canopy_curve_key])
  end
end
