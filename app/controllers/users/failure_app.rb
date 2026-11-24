module Users
  # Devise's answer to a request that isn't signed in. A page is sent to sign in, as always. A save
  # from a page still open after its session ended (Inertia's POST, PATCH or DELETE) gets a plain
  # 401 instead, which the frontend answers by saying so and leaving the page as it is
  # (entrypoints/inertia.ts): a redirect would replace the page and drop what's typed there. It
  # couldn't be followed in any case: Warden sits outside Inertia's middleware, so its 302 isn't
  # made a 303, and the browser repeats a PATCH or DELETE at the sign-in page, a 404.
  class FailureApp < Devise::FailureApp
    def http_auth?
      (inertia_save? && !warden_options[:recall]) || super
    end

    private

    # A sign-in form's own failure (recall) goes back to the form with its message
    def inertia_save? = request.headers["X-Inertia"].present? && !request.get? && !request.head?
  end
end
