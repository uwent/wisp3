# Irrigation entered once for a pivot (D9). Creating one for a date that already has one replaces it.
class PivotIrrigationsController < AuthenticatedController
  before_action :set_pivot

  def create
    save(@pivot.pivot_irrigations.find_or_initialize_by(date: irrigation_params[:date]))
  end

  def update
    save(@pivot.pivot_irrigations.find(params[:id]))
  end

  def destroy
    @pivot.pivot_irrigations.find(params[:id]).destroy!
    redirect_back_or_to pivot_path(@pivot), notice: "Irrigation deleted"
  end

  private

  def set_pivot
    @pivot = Current.group.pivots.find(params[:pivot_id])
  end

  def save(irrigation)
    irrigation.assign_attributes(irrigation_params)
    if irrigation.save
      redirect_back_or_to pivot_path(@pivot), notice: "Irrigation saved"
    else
      redirect_with_errors(request.referer || pivot_path(@pivot), irrigation)
    end
  end

  # field_ids: every field under the pivot, or none sent, means "all" (stored as NULL)
  def irrigation_params
    values = params.expect(pivot_irrigation: [:date, :inches, :run_hours, :notes, field_ids: []])
    values[:field_ids] = PivotIrrigation.normalize_field_ids(@pivot, values[:field_ids])
    values
  end
end
