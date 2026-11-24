# An irrigation system's irrigation on its page: one date's amounts on the fields it watered that
# day (IrrigationSystem#fields_on), saved as each field's own (D15: irrigation is stored per field and plot;
# Field#record_entry also sets the field's plots that had its amount), or on a field with nothing of
# its own to water (a rainfed crop, or only plots), its irrigated plots'
# (Field#record_system_irrigation). The list is the fields'
# entries by date (SystemsController#show); the export is SystemIrrigationCsv.
class SystemIrrigationsController < AuthenticatedController
  allow_example :index
  before_action :set_system

  # The year's irrigation (?year=) as CSV
  def index
    year = requested_year
    csv = SystemIrrigationCsv.new(@system, year, exported_by: current_user, about_url:).to_csv
    send_csv csv, "wisp-irrigation-#{@system.name.parameterize}-#{year}.csv"
  end

  # irrigation: {date, fields: {field_id => inches, blank for none}, from: the date being edited,
  # when it moved}. Fields not on the system that day are ignored.
  def create
    values = params.expect(irrigation: [:date, :from, fields: {}])
    date = parse_date(values[:date])
    return redirect_with_errors(request.referer || system_path(@system), {date: ["is needed"]}) unless date
    from = parse_date(values[:from])
    amounts = values[:fields].to_h
    errors = {}
    ApplicationRecord.transaction do
      clear(from) if from && from != date
      @system.fields_on(date).each do |field|
        next unless amounts.key?(field.id.to_s)
        entry = field.record_system_irrigation(date, amounts[field.id.to_s].presence)
        entry.errors.to_hash(true).each { |attribute, messages| errors["fields.#{field.id}.#{attribute}"] = messages }
      end
      raise ActiveRecord::Rollback if errors.any?
    end
    if errors.empty?
      redirect_back_or_to system_path(@system), notice: "Irrigation saved"
    else
      redirect_with_errors(request.referer || system_path(@system), errors)
    end
  end

  # Clears the irrigation on the system's fields that day (and their plots that had the same)
  def destroy
    date = parse_date(params[:date]) or raise ActionController::BadRequest, "Invalid date"
    ApplicationRecord.transaction { clear(date) }
    redirect_back_or_to system_path(@system), notice: "Irrigation deleted"
  end

  private

  def set_system
    @system = Current.group.systems.includes(:fields, farm: :group).find(params[:system_id])
  end

  def clear(date)
    @system.fields_on(date).each { |field| field.record_system_irrigation(date, nil) }
  end
end
