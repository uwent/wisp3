module Admin
  # Pages for WISP staff (users.admin). Everyone else gets a 404, so the pages aren't advertised.
  class BaseController < AuthenticatedController
    before_action :require_admin

    private

    def require_admin
      raise ActionController::RoutingError, "Not found" unless current_user.admin?
    end
  end
end
