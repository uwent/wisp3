# Base for every signed-in page. Sets Current.group from the session, but only ever to a
# group the user is a member of, so every group-scoped query starts from a group they own.
class AuthenticatedController < InertiaController
  before_action :authenticate_user!
  before_action :set_current_group

  private

  def set_current_group
    Current.user = current_user
    groups = current_user.groups
    Current.group = groups.find_by(id: session[:group_id]) || groups.order(:id).first
    session[:group_id] = Current.group&.id
  end
end
