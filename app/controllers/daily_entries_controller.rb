# Bulk daily entry (PLAN.md §11, Phase 8 G.4): one date for the whole operation. Each pivot has one
# irrigation (inches or run hours, for all its fields or some), each field its own rain, irrigation
# override and soil moisture reading, each part-field planting its own irrigation and soil moisture,
# and each planting a canopy reading (percent cover or LAI). Props: DailyEntryPage.
class DailyEntriesController < AuthenticatedController
  def show
    date = parse_date(params[:date]) || Date.current
    page = DailyEntryPage.new(Current.group, date)
    WeatherCell.keep_current(page.pivots.map(&:weather_cell_id))
    render inertia: "DailyEntries/Show", props: page.props
  end

  def update
    date = parse_date(params.expect(:date)) or raise ActionController::BadRequest, "Invalid date"
    errors = {}
    PivotIrrigation.transaction do
      record_pivots(date, errors)
      record_fields(date, errors)
      record_plantings(date, errors)
      record_canopy(date, errors)
      raise ActiveRecord::Rollback if errors.any?
    end

    if errors.any?
      redirect_with_errors daily_entry_path(date:), errors
    else
      redirect_to daily_entry_path(date:), notice: "Saved #{date.to_fs(:long)}"
    end
  end

  private

  # {"id" => {attribute => value}} for the pivots or fields sent, with only these attributes; an id
  # sent without a hash of values is dropped
  def by_id(key, attributes)
    values = params[key]
    return {} unless values.is_a?(ActionController::Parameters)
    values.permit(values.keys.index_with { attributes }).to_h
  end

  def parse_date(value)
    Date.iso8601(value.to_s) if value.present?
  rescue Date::Error
    nil
  end

  # A pivot sent with neither inches nor run hours has its irrigation for the day removed
  def record_pivots(date, errors)
    values = by_id(:pivots, [:inches, :run_hours, :notes, field_ids: []])
    Current.group.pivots.where(id: values.keys).find_each do |pivot|
      submitted = values[pivot.id.to_s]
      irrigation = pivot.pivot_irrigations.find_or_initialize_by(date:)
      if submitted["inches"].blank? && submitted["run_hours"].blank?
        irrigation.destroy! if irrigation.persisted?
        next
      end
      submitted["field_ids"] = PivotIrrigation.normalize_field_ids(pivot, submitted["field_ids"], date)
      next if irrigation.update(submitted)
      irrigation.errors.to_hash(true).each { |attribute, messages| errors["pivots.#{pivot.id}.#{attribute}"] = messages }
    end
  end

  # A part-field planting's own irrigation and soil moisture (a whole-field planting's are the field's)
  def record_plantings(date, errors)
    values = by_id(:plantings, %i[irrigation_in soil_moisture_pct])
    Current.group.plantings.where(id: values.keys, partial: true).find_each do |planting|
      entry = PlantingEntry.record(planting.planting_entries, date, values[planting.id.to_s])
      entry.errors.to_hash(true).each { |attribute, messages| errors["plantings.#{planting.id}.#{attribute}"] = messages }
    end
  end

  # {planting_id => value}: percent cover or LAI by the planting's ET method; blank removes the reading
  def record_canopy(date, errors)
    values = params[:canopy]
    return unless values.is_a?(ActionController::Parameters)
    values = values.permit(*values.keys).to_h
    Current.group.plantings.where(id: values.keys).find_each do |planting|
      observation = CanopyObservation.record(planting, date, values[planting.id.to_s])
      errors["canopy.#{planting.id}"] = observation.errors.full_messages if observation.errors.any?
    end
  end

  def record_fields(date, errors)
    values = by_id(:fields, DailyEntry::VALUES)
    Current.group.fields.where(id: values.keys).find_each do |field|
      entry = FieldEntry.record(field.field_entries, date, values[field.id.to_s])
      entry.errors.to_hash(true).each { |attribute, messages| errors["fields.#{field.id}.#{attribute}"] = messages }
    end
  end
end
