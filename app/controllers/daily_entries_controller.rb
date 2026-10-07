# Bulk daily entry (PLAN.md §11): one date for the whole operation. Each pivot has one irrigation
# (inches or run hours, for all its fields or some), and each field its own rain, irrigation
# override and soil moisture reading.
class DailyEntriesController < AuthenticatedController
  def show
    date = parse_date(params[:date]) || Date.current
    farms = Current.group.farms.order(:name).includes(pivots: [:weather_cell, {fields: {plantings: :plant}}])
    pivots = farms.flat_map(&:pivots)
    WeatherCell.keep_current(pivots.map(&:weather_cell_id))
    irrigations = PivotIrrigation.where(pivot: pivots, date:).index_by(&:pivot_id)
    entries = FieldEntry.where(field_id: pivots.flat_map(&:field_ids), date:).index_by(&:field_id)
    rain = WeatherDay.where(weather_cell_id: pivots.map(&:weather_cell_id), date:).pluck(:weather_cell_id, :precip_in).to_h

    render inertia: "DailyEntries/Show", props: {
      date:,
      farms: farms.map do |farm|
        {id: farm.id, name: farm.name, pivots: farm.pivots.map do |pivot|
          irrigation = irrigations[pivot.id]
          {id: pivot.id, name: pivot.name, pump_capacity_gpm: pivot.pump_capacity_gpm,
           irrigation: irrigation && PivotIrrigationSerializer.new(irrigation).to_h,
           fields: pivot.fields.map do |field|
             entry = entries[field.id]
             {id: field.id, name: field.name, area_acres: field.area_acres, crop: field.planting_on(date)&.plant&.name,
              # Only as a hint where the balance would use it (Q7: not on a field using entered rain, through today)
              rain_model: (field.effective_use_model_precip || date > Date.current) ? rain[pivot.weather_cell_id] : nil,
              entry: entry&.slice(:rain_in, :irrigation_in, :soil_moisture_pct, :notes)}
           end}
        end}
      end
    }
  end

  def update
    date = parse_date(params.expect(:date)) or raise ActionController::BadRequest, "Invalid date"
    errors = {}
    PivotIrrigation.transaction do
      record_pivots(date, errors)
      record_fields(date, errors)
      raise ActiveRecord::Rollback if errors.any?
    end

    if errors.any?
      redirect_with_errors daily_entry_path(date:), errors
    else
      redirect_to daily_entry_path(date:), notice: "Saved #{date.to_fs(:long)}"
    end
  end

  private

  def parse_date(value)
    Date.iso8601(value.to_s) if value.present?
  rescue Date::Error
    nil
  end

  # A pivot sent with neither inches nor run hours has its irrigation for the day removed
  def record_pivots(date, errors)
    values = params.fetch(:pivots, {}).permit!.to_h
    Current.group.pivots.where(id: values.keys).find_each do |pivot|
      submitted = values[pivot.id.to_s].slice("inches", "run_hours", "field_ids", "notes")
      irrigation = pivot.pivot_irrigations.find_or_initialize_by(date:)
      if submitted["inches"].blank? && submitted["run_hours"].blank?
        irrigation.destroy! if irrigation.persisted?
        next
      end
      submitted["field_ids"] = PivotIrrigation.normalize_field_ids(pivot, submitted["field_ids"])
      next if irrigation.update(submitted)
      irrigation.errors.to_hash(true).each { |attribute, messages| errors["pivots.#{pivot.id}.#{attribute}"] = messages }
    end
  end

  def record_fields(date, errors)
    values = params.fetch(:fields, {}).permit!.to_h
    Current.group.fields.where(id: values.keys).find_each do |field|
      entry = FieldEntry.record(field.field_entries, date, values[field.id.to_s].slice(*DailyEntry::VALUES.map(&:to_s)))
      entry.errors.to_hash(true).each { |attribute, messages| errors["fields.#{field.id}.#{attribute}"] = messages }
    end
  end
end
