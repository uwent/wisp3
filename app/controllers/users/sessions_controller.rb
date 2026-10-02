module Users
  # Password sign-in. Failed attempts are handled by Devise's failure app, which redirects
  # back here with an alert.
  class SessionsController < Devise::SessionsController
    include InertiaDeviseResponses

    def new
      render inertia: "Auth/SignIn", props: {email: params[:email].to_s}
    end
  end
end
