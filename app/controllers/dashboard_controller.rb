# Every field's water status today (PLAN.md §11), by farm and pivot: one card per field with this
# season's planting.
class DashboardController < AuthenticatedController
  def show
    overview = OperationOverview.new(Current.group)
    render inertia: "Dashboard/Show", props: {today: overview.today, farms: overview.props}
  end
end
