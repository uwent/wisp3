class PlantingsController < AuthenticatedController
  def create
    field = Current.group.fields.find(planting_params[:field_id])
    plant = Plant.find_by(id: planting_params[:plant_id])
    year = params.fetch(:year, Date.current.year).to_i
    defaults = plant ? Planting.defaults_for(plant, year) : {}
    planting = field.plantings.build(defaults.merge(planting_params.compact_blank.except(:field_id)))
    if planting.save
      redirect_back_or_to setup_path(year:), notice: "Added #{plant.name} on #{field.name}"
    else
      redirect_with_errors(request.referer || setup_path(year:), planting)
    end
  end

  def update
    planting = Current.group.plantings.find(params[:id])
    if planting.update(planting_params.except(:field_id))
      redirect_back_or_to setup_path(year: planting.season_year), notice: "Saved"
    else
      redirect_with_errors(request.referer || setup_path, planting)
    end
  end

  def destroy
    planting = Current.group.plantings.find(params[:id])
    planting.destroy!
    redirect_to setup_path(year: planting.season_year), notice: "Deleted #{planting.plant.name} on #{planting.field.name}"
  end

  # The season's daily balance as CSV (the legacy export's columns, plus where each value came from)
  def export
    planting = Current.group.plantings.includes(:plant, field: [:soil_type, {pivot: :farm}]).find(params[:id])
    filename = "wisp-#{planting.field.name.parameterize}-#{planting.season_year}.csv"
    send_data PlantingCsv.new(PlantingStatus.new(planting)).to_csv, filename:, type: "text/csv"
  end

  private

  def planting_params
    params.expect(planting: [:field_id, :plant_id, :variety, :season_start, :emergence_date, :end_date,
      :max_root_zone_depth, :mad_frac, :et_method, :target_ad_pct, :initial_moisture_pct, :notes])
  end
end
