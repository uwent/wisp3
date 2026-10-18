# Public pages (PLAN.md Phase 6.5): the landing page for signed-out visitors and the About page,
# which anyone can read. Signed in, the About page shows the app's nav, so the current operation
# is set as on every other page.
class PagesController < AuthenticatedController
  # Days after emergence shown on the About page's canopy curves
  CURVE_DAYS = 150

  skip_before_action :authenticate_user!
  skip_before_action :set_current_group, unless: :user_signed_in?

  def home
    render inertia: "Pages/Home"
  end

  def about
    render inertia: "Pages/About", props: {
      plants: Plant.order(:name).map do |plant|
        {key: plant.key, name: plant.name, root_zone_in: plant.default_max_root_zone_depth,
         lai_curve: plant.canopy_model.present?, cover_curve: CanopyCurve.for(plant.key).present?}
      end,
      canopy_curves: canopy_curves,
      soil_types: SoilType.order(:field_capacity, :perm_wilting_pt).map do |soil|
        {key: soil.key, name: soil.name, field_capacity: soil.field_capacity, perm_wilting_pt: soil.perm_wilting_pt,
         basis: SoilType.bases[soil.key]}
      end,
      defaults: {
        mad_pct: (Planting::DEFAULT_MAD_FRAC * 100).round,
        lead_days: PlantingStatus::LEAD_DAYS,
        forecast_days: Weather::Fetcher::FORECAST_DAYS,
        shift_warning_days: Canopy::SHIFT_WARNING_DAYS,
        drop_warning: Canopy::DROP_WARNING.round
      }
    }
  end

  private

  # Each crop's percent cover curve for the About page (PLAN.md Phase 6.7): its parameters, sources and
  # confidence from db/reference/canopy_curves.yml, and its cover by day for a May 15 emergence
  def canopy_curves
    emergence = Date.new(Date.current.year, 5, 15)
    Plant.order(:name).filter_map do |plant|
      curve = CanopyCurve.for(plant.key) or next
      covers = (0..CURVE_DAYS).map { |day| curve.cover(emergence, emergence + day).round(1) }
      {key: plant.key, name: plant.name, basis: curve.basis, confidence: curve.confidence,
       confidence_label: curve.confidence_label, notes: curve.notes,
       growth: {cc0: curve.cc0, ccx: curve.ccx, cgc: curve.cgc}, decline: curve.decline,
       days_to: [50, 80].to_h { |pct| [pct, covers.index { |cover| cover >= pct }] },
       covers:, sources: curve.sources.map { |source| {citation: source.citation, url: source.url} }}
    end
  end
end
