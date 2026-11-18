module Admin
  # How growers use WISP in a season (UsageReport, PLAN.md H.3): accounts, the onboarding funnel,
  # weekly activity and entries, the parts of WISP used and how operations are set up
  class UsageController < BaseController
    def show
      render inertia: "Admin/Usage", props: UsageReport.new(requested_year).props
    end
  end
end
