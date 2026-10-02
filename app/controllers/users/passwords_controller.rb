module Users
  # "Forgot password" and the reset form linked from the email. Devise is in paranoid mode, so
  # requesting a reset never reveals whether an account exists.
  class PasswordsController < Devise::PasswordsController
    include InertiaDeviseResponses

    def new
      render inertia: "Auth/ForgotPassword", props: {email: params[:email].to_s}
    end

    def edit
      render inertia: "Auth/ResetPassword", props: {
        reset_password_token: params[:reset_password_token].to_s,
        minimum_password_length: resource_class.password_length.min
      }
    end

    private

    def form_path_for_errors
      if action_name == "update"
        edit_user_password_path(reset_password_token: params.dig(:user, :reset_password_token))
      else
        new_user_password_path
      end
    end
  end
end
