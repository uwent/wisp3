# Public pages (PLAN.md Phase 6.5): the landing page for signed-out visitors and the About page,
# which anyone can read. Signed in, the About page shows the app's nav, so the current operation
# is set as on every other page.
class PagesController < AuthenticatedController
  skip_before_action :authenticate_user!
  skip_before_action :set_current_group, unless: :user_signed_in?

  def home
    render inertia: "Pages/Home"
  end

  def about
    render inertia: "Pages/About", props: {
      plants: Plant.order(:name).map do |plant|
        {key: plant.key, name: plant.name, root_zone_in: plant.default_max_root_zone_depth,
         lai_curve: plant.canopy_model.present?}
      end,
      defaults: {
        mad_pct: (Planting::DEFAULT_MAD_FRAC * 100).round,
        lead_days: PlantingStatus::LEAD_DAYS,
        forecast_days: Weather::Fetcher::FORECAST_DAYS
      }
    }
  end
end
