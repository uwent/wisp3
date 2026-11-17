# Base for every signed-in page. Sets Current.group from the session, but only ever to a
# group the user is a member of, so every group-scoped query starts from a group they own.
class AuthenticatedController < InertiaController
  before_action :authenticate_user!
  before_action :set_current_group

  private

  def set_current_group
    Current.user = current_user
    memberships = current_user.memberships.includes(:group)
    # Someone removed from their last group gets a fresh one of their own
    current_user.create_personal_group if memberships.none?
    # Links from emails name the record's group (?operation=), which may not be the current one
    Current.membership = memberships.find_by(group_id: params[:operation]) if params[:operation].is_a?(String)
    Current.membership ||= memberships.find_by(group_id: session[:group_id]) || memberships.order(:group_id).first
    Current.group = Current.membership.group
    session[:group_id] = Current.group.id
  end

  # For actions only the group's owners may take (Q8)
  def require_owner
    return if Current.owner?

    redirect_back_or_to root_path, alert: "Only an owner of #{Current.group.name} can do that.", status: :see_other
  end

  # Deleting a planting or an irrigation group: its group's owners, or the member who created it
  # (G.15). False after redirecting, so the action returns.
  def owner_or_creator?(record)
    return true if Current.owner? || (record.created_by_id && record.created_by_id == Current.user.id)

    redirect_back_or_to root_path, alert: "Only an owner of #{Current.group.name} or the person who added it can delete it.",
      status: :see_other
    false
  end
end
