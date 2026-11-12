# Pivot groups (PLAN.md Phase 8 G.4), managed in Setup: a name and which of the farm's pivots share
# the group's rain gauge. A pivot joining a group leaves any other; deleting a group ungroups its
# pivots.
class PivotGroupsController < AuthenticatedController
  def create
    farm = Current.group.farms.find(params.expect(pivot_group: [:farm_id])[:farm_id])
    save(farm.pivot_groups.build, "Added")
  end

  def update
    save(Current.group.pivot_groups.find(params[:id]), "Saved")
  end

  def destroy
    pivot_group = Current.group.pivot_groups.find(params[:id])
    pivot_group.destroy!
    redirect_to setup_path, notice: "Deleted #{pivot_group.name}; its irrigation systems are no longer grouped"
  end

  private

  def save(pivot_group, done)
    values = params.expect(pivot_group: [:name, pivot_ids: []])
    saved = PivotGroup.transaction do
      next false unless pivot_group.update(name: values[:name])
      assign_pivots(pivot_group, values[:pivot_ids]) if values.key?(:pivot_ids)
      true
    end
    if saved
      redirect_to setup_path, notice: "#{done} #{pivot_group.name}"
    else
      redirect_with_errors setup_path, pivot_group
    end
  end

  # Exactly these of the farm's pivots are in the group (the form sends a blank sentinel, so none
  # checked is an empty list); other farms' or operations' pivots are ignored
  def assign_pivots(pivot_group, ids)
    ids = Array(ids).compact_blank.map(&:to_i)
    pivots = pivot_group.farm.pivots
    pivots.where(pivot_group:).where.not(id: ids).update_all(pivot_group_id: nil)
    pivots.where(id: ids).update_all(pivot_group_id: pivot_group.id)
  end
end
