# Every field's water status today (PLAN.md §11), by farm and pivot: one card per field with this
# season's planting.
class DashboardController < AuthenticatedController
  def show
    overview = OperationOverview.new(Current.group)
    render inertia: "Dashboard/Show", props: {
      today: overview.today, farms: overview.props, getting_started: getting_started(overview)
    }
  end

  private

  # Until the operation has any planting, what's set up so far, for the checklist (PLAN.md G.6)
  def getting_started(overview)
    fields = overview.pivots.flat_map(&:fields)
    return if fields.any? { |field| field.plantings.any? }

    {farms: overview.farms.size, systems: overview.pivots.size, fields: fields.size}
  end
end
