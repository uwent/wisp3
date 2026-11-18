module Users
  # Sign-up, plus email/password changes and account deletion from the Settings page
  class RegistrationsController < Devise::RegistrationsController
    include InertiaDeviseResponses

    before_action :permit_profile_params
    before_action :forbid_while_impersonating, only: [:update, :destroy]
    before_action :turn_away_bots, only: :create

    def new
      render inertia: "Auth/SignUp", props: {
        minimum_password_length: resource_class.password_length.min,
        form_token: (session[:sign_up_form_token] = SignUpGuard.token(session[:sign_up_form_token]))
      }
    end

    # Email and password are edited on the Settings page
    def edit
      redirect_to settings_path
    end

    protected

    def after_inactive_sign_up_path_for(_resource)
      session.delete(:sign_up_form_token)
      new_user_session_path
    end

    def after_update_path_for(_resource)
      settings_path
    end

    private

    def form_path_for_errors
      (action_name == "create") ? new_user_registration_path : settings_path
    end

    # A bot is told it signed up (so it doesn't learn to dodge the check) and nothing is created
    def turn_away_bots
      case SignUpGuard.check(token: params[:form_token], honeypot: params[SignUpGuard::HONEYPOT])
      when :bot
        Rails.logger.info("Sign-up turned away as automated (#{request.remote_ip})")
        redirect_to new_user_session_path, notice: I18n.t("devise.registrations.signed_up_but_unconfirmed"), status: :see_other
      when :stale
        redirect_to new_user_registration_path, status: :see_other,
          alert: "This form was open too long, or didn't load completely. Please fill it in again."
      end
    end

    def permit_profile_params
      devise_parameter_sanitizer.permit(:sign_up, keys: [:first_name, :last_name])
    end
  end
end
