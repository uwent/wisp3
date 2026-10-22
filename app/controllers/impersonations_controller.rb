# Returning to admin after signing in as someone else (Admin::ImpersonationsController#create). The
# signed-in user isn't an admin, so this isn't under Admin::. If the admin has been deleted or is no
# longer one, it signs out instead.
class ImpersonationsController < AuthenticatedController
  def destroy
    return redirect_to(root_path, status: :see_other) unless session[:impersonated_id] == current_user.id

    user = current_user
    admin = impersonator
    group_id = session[:impersonator_group_id]
    clear_impersonation
    unless admin
      sign_out(:user)
      return redirect_to(new_user_session_path, status: :see_other)
    end

    request.env["devise.skip_trackable"] = true
    sign_in(:user, admin)
    session[:group_id] = group_id
    Rails.logger.info("Impersonation ended: admin #{admin.id} as user #{user.id}")
    redirect_to admin_user_path(user), notice: "You're back as #{admin.email}.", status: :see_other
  end
end
