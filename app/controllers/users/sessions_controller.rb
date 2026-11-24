module Users
  # Password sign-in. Failed attempts are handled by Devise's failure app, which redirects
  # back here with an alert.
  class SessionsController < Devise::SessionsController
    include InertiaDeviseResponses

    def new
      render inertia: "Auth/SignIn", props: {email: params[:email].to_s}
    end

    private

    # Signing out throws away the key to the pages kept in the browser's history (encrypt_history),
    # so Back on a shared computer doesn't show the last person's farms
    def respond_to_on_destroy(**)
      redirect_to after_sign_out_path_for(resource_name), status: :see_other, inertia: {clear_history: true}
    end
  end
end
