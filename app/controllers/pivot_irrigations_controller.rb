# Irrigation entered once for a pivot (D9). Creating one for a date that already has one replaces it.
# The form also sets each field's own amount that day (field_amounts: {field_id => {irrigation_in,
# irrigation_pct}}, blank for the system's), saved as the field's entry, which replaces the
# system's for that field (DailyInputs), as daily entry's field rows do.
class PivotIrrigationsController < AuthenticatedController
  allow_example :index
  before_action :set_pivot

  # The year's irrigation (?year=) as CSV
  def index
    year = requested_year
    irrigations = PivotIrrigation.preload_areas(@pivot.pivot_irrigations.where(date: Date.new(year).all_year).order(:date))
    csv = PivotIrrigationCsv.new(@pivot, year, irrigations, exported_by: current_user, about_url:).to_csv
    send_csv csv, "wisp-irrigation-#{@pivot.name.parameterize}-#{year}.csv"
  end

  def create
    save(@pivot.pivot_irrigations.find_or_initialize_by(date: irrigation_params[:date]))
  end

  def update
    save(@pivot.pivot_irrigations.find(params[:id]))
  end

  # The fields' own amounts that day go with it
  def destroy
    irrigation = @pivot.pivot_irrigations.find(params[:id])
    PivotIrrigation.transaction do
      clear_field_amounts(irrigation.date)
      irrigation.destroy!
    end
    redirect_back_or_to pivot_path(@pivot), notice: "Irrigation deleted"
  end

  private

  def set_pivot
    @pivot = Current.group.pivots.includes(:fields, farm: :group).find(params[:pivot_id])
  end

  # field_ids: every field on the pivot that day, or none sent, means "all" (stored as NULL)
  def save(irrigation)
    values = irrigation_params
    irrigation.assign_attributes(values.except(:field_ids))
    irrigation.field_ids = PivotIrrigation.normalize_field_ids(@pivot, values[:field_ids], irrigation.date)
    moved_from = irrigation.date_in_database if irrigation.persisted? && irrigation.date_changed?
    errors = {}
    PivotIrrigation.transaction do
      if irrigation.save
        clear_field_amounts(moved_from) if moved_from
        record_field_amounts(irrigation.date, errors)
      else
        errors = irrigation.errors.to_hash(true)
      end
      raise ActiveRecord::Rollback if errors.any?
    end
    if errors.empty?
      redirect_back_or_to pivot_path(@pivot), notice: "Irrigation saved"
    else
      redirect_with_errors(request.referer || pivot_path(@pivot), errors)
    end
  end

  # Each field on the system that day: its own amount, or blank for the system's (clearing one saved
  # before). Through DailyEntrySave, so a percent becomes the inches it puts on; errors come back as
  # fields.<id>.irrigation_in.
  def record_field_amounts(date, errors)
    amounts = params.dig(:pivot_irrigation, :field_amounts)
    return unless amounts.is_a?(ActionController::Parameters)
    allowed = @pivot.fields_on(date).map { |field| field.id.to_s }
    # A percent not sent is kept unless the inches change (DailyEntry.record)
    fields = amounts.to_unsafe_h.slice(*allowed).transform_values do |amount|
      amount.slice(:irrigation_in, :irrigation_pct).transform_values(&:presence)
    end
    DailyEntrySave.new(Current.group, date).record(ActionController::Parameters.new(fields:), errors)
  end

  def clear_field_amounts(date)
    @pivot.fields_on(date).each do |field|
      FieldEntry.record(field.field_entries, date, irrigation_in: nil, irrigation_pct: nil)
    end
  end

  def irrigation_params
    params.expect(pivot_irrigation: [:date, *PivotIrrigation::AMOUNTS, :notes, field_ids: []])
  end
end
