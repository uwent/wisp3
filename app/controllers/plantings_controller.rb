class PlantingsController < AuthenticatedController
  allow_example :show, :export

  # A planting's page: its season with the summary, daily grid,
  # chart and the week ahead (its zone's panels are on the weather page). ?as_of= travels back
  # to a day of the season before today: the page shows the season as it stood
  # then, read-only. A date outside the season, ahead or malformed redirects without it. The example
  # farm shows its day that way when the season covers it, with no other day to pick.
  def show
    field_id = Current.group.plantings.where(id: params[:id]).pick(:field_id) or raise ActiveRecord::RecordNotFound
    field = Current.group.fields.with_season_tree.find(field_id)
    planting = field.plantings.find { |p| p.id == params[:id].to_i }
    past = parse_date(params[:as_of])&.then { |date| date if date < Current.today } unless Current.as_of
    as_of = Current.as_of || past
    as_of = nil unless planting.season_range.cover?(as_of)
    # An ?as_of= that can't be used leaves the URL, so it doesn't look like time travel
    return redirect_to planting_path(planting, request.query_parameters.except("as_of")) if params.key?(:as_of) && !as_of

    weather_updating = !as_of && WeatherCell.keep_current_updating_ids([field.pivot.weather_cell_id]).any?

    render inertia: "Plantings/Show", props: {
      **FieldHeaderProps.for(field),
      weather_updating:,
      as_of:,
      travel_dates: Current.as_of ? nil : travel_dates(planting),
      planting: PlantingSerializer.new(planting).to_h,
      # Part-field plantings on the field at once add up to more than its area (a warning)
      exceeds_field_area: planting.exceeds_field_area?,
      # The zone the season ran on, and its week ahead for this year's plantings, ended ones
      # too, as on the field page, but not while time travelling
      **WeatherZone.page_props(Current.group, planting.weather_cell,
        forecast: (Current.as_of.present? || !as_of) && planting.season_year == Current.today.year),
      **season_props(field, planting, as_of)
    }
  end

  # replace: end the plantings this one overlaps the day before it starts ("Replace" on the form),
  # in the same transaction. also_field_ids: other fields to plant the same on (a new
  # whole-field planting only), each an independent planting on its own field's soil and area,
  # saved with this one or not at all; replace applies only to this one.
  def create
    field = Current.group.fields.find(planting_params[:field_id])
    year = requested_year
    planting = Planting.build_for(field, planting_params.compact_blank.except(:field_id), year:, created_by: Current.user)
    copies = copies_of(planting) or raise ActiveRecord::RecordNotFound
    errors = {}
    saved = Planting.transaction do
      planting.replace_overlapping! if params[:replace].present?
      planting.save || raise(ActiveRecord::Rollback)
      copies.each { |copy| copy.save || errors.merge!(copy_errors(copy)) }
      errors.empty? || raise(ActiveRecord::Rollback)
    end
    if saved
      redirect_back_or_to setup_path(year:), notice: added_notice(planting, copies)
    elsif errors.any?
      redirect_with_errors(request.referer || setup_path(year:), errors)
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
    return unless owner_or_creator?(planting)

    planting.destroy!
    redirect_back_or_to setup_path(year: planting.season_year), notice: "Deleted #{planting.plant.name} on #{planting.field.name}"
  end

  # The season's daily balance as CSV (the legacy export's columns, plus where each value came from)
  def export
    planting = Current.group.plantings.includes(:plant, pivot: {farm: :group}, field: [:soil_type, {pivot: [:pivot_group, {farm: :group}]}]).find(params[:id])
    filename = "wisp-#{planting.field.name.parameterize}-#{planting.season_year}.csv"
    csv = PlantingCsv.new(PlantingStatus.new(planting), exported_by: current_user, about_url:).to_csv
    send_csv csv, filename
  end

  private

  # The days of the season before today, which ?as_of= can pick ({from:, to:}), or nil if none
  def travel_dates(planting)
    to = [planting.end_date, Current.today - 1].min
    {from: planting.season_start, to:} if to >= planting.season_start
  end

  # as_of: time travelling, the days run to the end of the days that followed it, and canopy readings
  # stop at it
  def season_props(field, planting, as_of)
    status = FieldStatuses.status(planting, today: Current.today, as_of:, ensemble: Current.as_of ? [] : :load)
    dates = as_of ? planting.season_start..[as_of + PlantingStatus::HORIZON, planting.end_date].min : planting.season_range
    attribute = (planting.et_method == "lai") ? :lai : :pct_cover
    field_entries = field.field_entries.where(date: dates).index_by(&:date)

    day_params = {
      # Notes: a part-field planting's own, else the field's
      entries: planting.partial? ? planting.planting_entries.where(date: dates).index_by(&:date) : field_entries,
      observations: planting.canopy_observations.select { |obs| dates.cover?(obs.date) && (!as_of || obs.date <= as_of) }
        .to_h { |obs| [obs.date, obs[attribute]] }.compact,
      # A part-field planting's view of the field's irrigation, shown under its own
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

  # The values a planting on several fields shares; the rest (soil, area, plot, notes) is each field's
  COPIED = %w[plant_id variety season_start emergence_date end_date vine_kill_date max_root_zone_depth mad_frac et_method
    canopy_interpolation canopy_curve_key season_days target_ad_pct initial_moisture_pct].freeze

  # The same planting on the other fields chosen (also_field_ids), built from its values (its crop's
  # defaults and suggested harvest already filled in); none for part of a field. nil if a field
  # isn't the group's.
  def copies_of(planting)
    ids = params[:also_field_ids]
    ids = ids.values if ids.is_a?(ActionController::Parameters) # indexed: also_field_ids[0]
    ids = Array(ids).compact_blank.map { |id| id.to_s.to_i }.uniq - [planting.field_id]
    return [] if ids.empty? || planting.partial?
    fields = Current.group.fields.where(id: ids).includes(plantings: :plant, pivot: :weather_cell).to_a
    return unless fields.size == ids.size

    values = planting.attributes.slice(*COPIED).symbolize_keys
    fields.sort_by(&:name).map { |field| Planting.build_for(field, values, year: planting.season_year, created_by: Current.user) }
  end

  # A copy's errors, keyed also.<field id>.<attribute> and naming its field ("East 40: overlaps its
  # Soybean planting")
  def copy_errors(copy)
    field = copy.field
    copy.errors.each_with_object({}) do |error, errors|
      overlapping = field.plantings.select { |other| other.persisted? && other.overlaps?(copy) }
      message = if error.attribute == :season_start && overlapping.any?
        "#{field.name}: overlaps its #{overlapping.map { |other| other.plant.name }.to_sentence} planting"
      else
        "#{field.name}: #{error.full_message}"
      end
      (errors["also.#{field.id}.#{error.attribute}"] ||= []) << message
    end
  end

  # "Added Corn on North 40", "… and East 40", "… and 3 other fields"
  def added_notice(planting, copies)
    notice = "Added #{planting.plant.name} on #{planting.field.name}"
    case copies.size
    when 0 then notice
    when 1 then "#{notice} and #{copies.first.field.name}"
    else "#{notice} and #{copies.size} other fields"
    end
  end

  def planting_params
    params.expect(planting: [:field_id, :plant_id, :variety, :season_start, :emergence_date, :end_date, :vine_kill_date,
      :max_root_zone_depth, :mad_frac, :et_method, :canopy_interpolation, :target_ad_pct, :initial_moisture_pct, :notes,
      :soil_type_id, :field_capacity, :perm_wilting_pt, :area_acres,
      :partial, :plot_length_ft, :plot_width_ft, :own_soil, :canopy_curve_key, :season_days])
  end
end
