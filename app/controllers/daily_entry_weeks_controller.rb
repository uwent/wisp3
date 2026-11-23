# Daily entry's week view: rain and irrigation for the seven days ending on ?date=
# (daily entry's day without one), for a grower back after a few days away or entering once a week.
# Props: DailyEntryWeek. The save sends only the cells changed, as each day's values under
# days[<date>] (the day page's names), saved by DailyEntrySave for every day in one transaction.
class DailyEntryWeeksController < AuthenticatedController
  def show
    week = DailyEntryWeek.new(Current.group, parse_date(params[:date]) || DailyEntryPage.default_date)
    WeatherCell.keep_current(week.systems.map(&:weather_cell_id))
    render inertia: "DailyEntries/Week", props: week.props
  end

  def update
    date = parse_date(params.expect(:date)) or raise ActionController::BadRequest, "Invalid date"
    dates = DailyEntryWeek.new(Current.group, date).dates
    days = params[:days].is_a?(ActionController::Parameters) ? params[:days] : {}
    errors = {}
    ApplicationRecord.transaction do
      days.each_key do |key|
        day = parse_date(key)
        raise ActionController::BadRequest, "#{key} isn't in the week" unless dates.include?(day)
        DailyEntrySave.new(Current.group, day, prefix: "days.#{key}.").record(days[key], errors)
      end
      raise ActiveRecord::Rollback if errors.any?
    end

    if errors.any?
      redirect_with_errors daily_entry_week_path(date:), errors
    else
      redirect_to daily_entry_week_path(date:), notice: "Saved #{week_label(dates)}"
    end
  end

  private

  # "Jul 14–20", "Jun 28–Jul 4", "Dec 29, 2025–Jan 4, 2026"
  def week_label(dates)
    first, last = dates.first, dates.last
    if first.year != last.year
      "#{first.strftime("%b %-d, %Y")}–#{last.strftime("%b %-d, %Y")}"
    elsif first.month != last.month
      "#{first.strftime("%b %-d")}–#{last.strftime("%b %-d")}"
    else
      "#{first.strftime("%b %-d")}–#{last.day}"
    end
  end
end
