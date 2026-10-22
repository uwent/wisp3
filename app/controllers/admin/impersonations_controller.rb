module Admin
  # Signing in as a user for support (PLAN.md Phase 8 B). The admin's id stays in the session so
  # ImpersonationsController#destroy can sign them back in; neither sign-in touches the user's
  # trackable sign-in count and times. Not for yourself or another admin.
  class ImpersonationsController < BaseController
    before_action :forbid_while_impersonating

    def create
      user = User.find(params[:user_id])
      if user == current_user || user.admin?
        return redirect_to admin_user_path(user), alert: "You can't sign in as yourself or another admin.",
          status: :see_other
      end

      admin = current_user
      session[:impersonator_id] = admin.id
      session[:impersonated_id] = user.id
      session[:impersonator_group_id] = session.delete(:group_id)
      request.env["devise.skip_trackable"] = true
      sign_in(:user, user)
      Rails.logger.info("Impersonation started: admin #{admin.id} as user #{user.id}")
      redirect_to root_path, notice: "You're signed in as #{user.email}.", status: :see_other
    end
  end
end
