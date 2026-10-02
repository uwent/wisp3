class DashboardController < AuthenticatedController
  def show
    render inertia: "Dashboard/Show"
  end
end
