# Switches which of the user's groups (farm operations) is active
class CurrentGroupsController < AuthenticatedController
  def update
    group = current_user.groups.find(params.expect(:group_id))
    session[:group_id] = group.id
    redirect_to root_path, notice: "Switched to #{group.name}"
  end
end
