class ApplicationController < ActionController::Base
  helper_method :impersonator

  private

  # The admin signed in as current_user for support (PLAN.md Phase 8 B), or nil. The session keys
  # count only while they name the signed-in user and an admin, so a stale pair (the impersonated
  # session timed out and remember-me signed the admin back in) never shows the bar; it's cleared.
  def impersonator
    return @impersonator if defined?(@impersonator)

    @impersonator = if session[:impersonator_id] && current_user && session[:impersonated_id] == current_user.id
      User.find_by(id: session[:impersonator_id], admin: true)
    end
    clear_impersonation if session[:impersonator_id] && @impersonator.nil?
    @impersonator
  end

  def clear_impersonation
    session.delete(:impersonator_id)
    session.delete(:impersonated_id)
    session.delete(:impersonator_group_id)
  end

  # For what an admin signed in as someone else mustn't do on their behalf: account credentials,
  # emails sent as them, and another impersonation
  def forbid_while_impersonating
    return unless impersonator

    redirect_back_or_to root_path, alert: "That's turned off while you're signed in as someone else.",
      status: :see_other
  end
end
