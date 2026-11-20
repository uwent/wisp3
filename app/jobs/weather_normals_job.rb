# Fetches a cell's temperature normals (Weather::Normals) if it has none, for canopy curves in
# thermal time. Queued with each update of a cell people look at (WeatherUpdateJob) and each
# scheduled refresh of the active cells, and by `bin/rails weather:normals`.
class WeatherNormalsJob < WeatherJob
  def perform(cell_id)
    cell = WeatherCell.find_by(id: cell_id) or return
    return if cell.normals?
    Weather::Normals.new.fetch(cell)
  end
end
