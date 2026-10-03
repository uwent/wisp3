module Users
  # Email confirmation links, and resending them
  class ConfirmationsController < Devise::ConfirmationsController
    include InertiaDeviseResponses

    def new
      render inertia: "Auth/ResendConfirmation", props: {email: params[:email].to_s}
    end

    # Landing page from the email. It only shows a button; confirming takes a POST, so email
    # security scanners that pre-fetch links can't use up the token.
    def show
      token = params[:confirmation_token].to_s
      user = resource_class.find_by(confirmation_token: token) if token.present?
      status = if user.nil? then "invalid"
      elsif user.confirmed? && user.unconfirmed_email.blank? then "confirmed"
      else "pending"
      end
      render inertia: "Auth/ConfirmEmail", props: {token:, status:}
    end

    def confirm
      self.resource = resource_class.confirm_by_token(params[:confirmation_token])
      if resource.errors.empty?
        set_flash_message!(:notice, :confirmed)
        redirect_to after_confirmation_path_for(resource_name, resource), status: :see_other
      elsif resource.errors.of_kind?(:email, :already_confirmed)
        redirect_to new_user_session_path, notice: "Your email address is already confirmed. You can sign in.", status: :see_other
      else
        redirect_to new_user_confirmation_path, status: :see_other,
          alert: "That confirmation link is invalid. Request a new one below, or sign in if you've already confirmed."
      end
    end

    private

    def form_path_for_errors
      new_user_confirmation_path
    end
  end
end
