# The operation's season as one CSV (SeasonReportCsv), linked from Setup
class SeasonReportsController < AuthenticatedController
  def show
    year = params.fetch(:year, Date.current.year).to_i
    csv = SeasonReportCsv.new(Current.group, year, exported_by: current_user, about_url:).to_csv
    send_data csv, filename: "wisp-season-#{Current.group.name.parameterize}-#{year}.csv", type: "text/csv; charset=utf-8"
  end
end
