# The operation's season as one CSV (SeasonReportCsv), linked from Setup
class SeasonReportsController < AuthenticatedController
  def show
    year = requested_year
    csv = SeasonReportCsv.new(Current.group, year, exported_by: current_user, about_url:).to_csv
    send_csv csv, "wisp-season-#{Current.group.name.parameterize}-#{year}.csv"
  end
end
