# Irrigation groups, managed in Setup: a name, which of the farm's systems share
# the group's rain gauge, and which rain their balances use (Q7; blank follows the operation). A system joining a group leaves any other; deleting a group ungroups its
# systems.
class IrrigationGroupsController < AuthenticatedController
  def create
    farm = Current.group.farms.find(params.expect(irrigation_group: [:farm_id])[:farm_id])
    save(farm.irrigation_groups.build(created_by: Current.user), "Added")
  end

  def update
    save(Current.group.irrigation_groups.find(params[:id]), "Saved")
  end

  def destroy
    irrigation_group = Current.group.irrigation_groups.find(params[:id])
    return unless owner_or_creator?(irrigation_group)

    irrigation_group.destroy!
    redirect_to setup_path, notice: "Deleted #{irrigation_group.name}; its irrigation systems are no longer grouped"
  end

  private

  def save(irrigation_group, done)
    values = params.expect(irrigation_group: [:name, :use_model_precip, system_ids: []])
    saved = IrrigationGroup.transaction do
      next false unless irrigation_group.update(values.slice(:name, :use_model_precip))
      assign_systems(irrigation_group, values[:system_ids]) if values.key?(:system_ids)
      true
    end
    if saved
      redirect_to setup_path, notice: "#{done} #{irrigation_group.name}"
    else
      redirect_with_errors setup_path, irrigation_group
    end
  end

  # Exactly these of the farm's systems are in the group (the form sends a blank sentinel, so none
  # checked is an empty list); other farms' or operations' systems are ignored
  def assign_systems(irrigation_group, ids)
    ids = Array(ids).compact_blank.map(&:to_i)
    systems = irrigation_group.farm.systems
    systems.where(irrigation_group:).where.not(id: ids).update_all(irrigation_group_id: nil)
    systems.where(id: ids).update_all(irrigation_group_id: irrigation_group.id)
  end
end
