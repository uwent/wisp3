module Users
  # Sign-up, plus email/password changes and account deletion from the Settings page
  class RegistrationsController < Devise::RegistrationsController
    include InertiaDeviseResponses

    before_action :permit_profile_params

    def new
      render inertia: "Auth/SignUp", props: {minimum_password_length: resource_class.password_length.min}
    end

    # Email and password are edited on the Settings page
    def edit
      redirect_to settings_path
    end

    protected

    def after_inactive_sign_up_path_for(_resource)
      new_user_session_path
    end

    def after_update_path_for(_resource)
      settings_path
    end

    private

    def form_path_for_errors
      (action_name == "create") ? new_user_registration_path : settings_path
    end

    def permit_profile_params
      devise_parameter_sanitizer.permit(:sign_up, keys: [:first_name, :last_name])
    end
  end
end
