# Which of the group's pivots have a weather update queued or running (WeatherCell.updating_ids), as
# JSON, for pages showing "Updating weather…" to ask every few seconds (lib/poll.ts). It reads only
# the cache, so a page reloads its data once an update lands rather than on every check.
class WeatherUpdatesController < AuthenticatedController
  def show
    cells = Current.group.pivots.pluck(:id, :weather_cell_id)
    updating = WeatherCell.updating_ids(cells.map(&:last)).to_set
    response.headers["Cache-Control"] = "no-store"
    render json: {pivot_ids: cells.filter_map { |id, cell_id| id if updating.include?(cell_id) }}
  end
end
