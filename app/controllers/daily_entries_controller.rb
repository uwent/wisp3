# Bulk daily entry: one date for the whole operation. Each field its own
# rain, irrigation and soil moisture reading, each part-field planting its own irrigation and soil
# moisture, and each planting a canopy reading (percent cover or LAI); a system's row fills its
# fields' boxes in the browser (D15). Props: DailyEntryPage; saved by
# DailyEntrySave. The week view is DailyEntryWeeksController.
class DailyEntriesController < AuthenticatedController
  def show
    date = parse_date(params[:date]) || DailyEntryPage.default_date
    page = DailyEntryPage.new(Current.group, date)
    WeatherCell.keep_current(page.pivots.map(&:weather_cell_id))
    render inertia: "DailyEntries/Show", props: page.props
  end

  def update
    date = parse_date(params.expect(:date)) or raise ActionController::BadRequest, "Invalid date"
    errors = {}
    ApplicationRecord.transaction do
      DailyEntrySave.new(Current.group, date).record(params, errors)
      raise ActiveRecord::Rollback if errors.any?
    end

    if errors.any?
      redirect_with_errors daily_entry_path(date:), errors
    else
      redirect_to daily_entry_path(date:), notice: "Saved #{date.to_fs(:long)}"
    end
  end
end
