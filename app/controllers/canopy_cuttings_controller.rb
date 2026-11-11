# Adds and removes a perennial planting's cuttings (PLAN.md Phase 8 G.3), from its page
class CanopyCuttingsController < AuthenticatedController
  def create
    planting = Current.group.plantings.find(params[:planting_id])
    cutting = planting.canopy_cuttings.build(params.expect(cutting: [:date]))
    if cutting.save
      redirect_to planting_path(planting), notice: "Cut on #{cutting.date.strftime("%b %-d")}"
    else
      redirect_with_errors planting_path(planting), cutting
    end
  end

  def destroy
    planting = Current.group.plantings.find(params[:planting_id])
    cutting = planting.canopy_cuttings.find(params[:id])
    cutting.destroy!
    redirect_to planting_path(planting), notice: "Removed the #{cutting.date.strftime("%b %-d")} cutting"
  end
end
