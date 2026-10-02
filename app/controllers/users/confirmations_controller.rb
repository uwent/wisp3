module Users
  # Email confirmation links, and resending them
  class ConfirmationsController < Devise::ConfirmationsController
    include InertiaDeviseResponses

    def new
      render inertia: "Auth/ResendConfirmation", props: {email: params[:email].to_s}
    end

    def show
      self.resource = resource_class.confirm_by_token(params[:confirmation_token])
      if resource.errors.empty?
        set_flash_message!(:notice, :confirmed)
        redirect_to after_confirmation_path_for(resource_name, resource), status: :see_other
      else
        redirect_to new_user_confirmation_path,
          alert: "That confirmation link is invalid or has already been used. Request a new one below, or sign in if you've already confirmed."
      end
    end

    private

    def form_path_for_errors
      new_user_confirmation_path
    end
  end
end
