# An irrigation system's irrigation on its page: one date's amounts on the fields it watered that
# day (Pivot#fields_on), saved as each field's own (D15: irrigation is stored per field and plot;
# Field#record_entry also sets the field's plots that had its amount). The list is the fields'
# entries by date (PivotsController#show); the export is PivotIrrigationCsv.
class PivotIrrigationsController < AuthenticatedController
  allow_example :index
  before_action :set_pivot

  # The year's irrigation (?year=) as CSV
  def index
    year = requested_year
    csv = PivotIrrigationCsv.new(@pivot, year, exported_by: current_user, about_url:).to_csv
    send_csv csv, "wisp-irrigation-#{@pivot.name.parameterize}-#{year}.csv"
  end

  # irrigation: {date, fields: {field_id => inches, blank for none}, from: the date being edited,
  # when it moved}. Fields not on the system that day are ignored.
  def create
    values = params.expect(irrigation: [:date, :from, fields: {}])
    date = parse_date(values[:date])
    return redirect_with_errors(request.referer || pivot_path(@pivot), {date: ["is needed"]}) unless date
    from = parse_date(values[:from])
    amounts = values[:fields].to_h
    errors = {}
    ApplicationRecord.transaction do
      clear(from) if from && from != date
      @pivot.fields_on(date).each do |field|
        next unless amounts.key?(field.id.to_s)
        entry = field.record_entry(date, {irrigation_in: amounts[field.id.to_s].presence})
        entry.errors.to_hash(true).each { |attribute, messages| errors["fields.#{field.id}.#{attribute}"] = messages }
      end
      raise ActiveRecord::Rollback if errors.any?
    end
    if errors.empty?
      redirect_back_or_to pivot_path(@pivot), notice: "Irrigation saved"
    else
      redirect_with_errors(request.referer || pivot_path(@pivot), errors)
    end
  end

  # Clears the irrigation on the system's fields that day (and their plots that had the same)
  def destroy
    date = parse_date(params[:date]) or raise ActionController::BadRequest, "Invalid date"
    ApplicationRecord.transaction { clear(date) }
    redirect_back_or_to pivot_path(@pivot), notice: "Irrigation deleted"
  end

  private

  def set_pivot
    @pivot = Current.group.pivots.includes(:fields, farm: :group).find(params[:pivot_id])
  end

  def clear(date)
    @pivot.fields_on(date).each { |field| field.record_entry(date, {irrigation_in: nil}) }
  end
end
