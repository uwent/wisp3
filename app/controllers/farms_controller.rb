class FarmsController < AuthenticatedController
  before_action :require_owner, only: :destroy

  def create
    farm = Current.group.farms.build(farm_params)
    if farm.save
      redirect_to setup_path, notice: "Added #{farm.name}"
    else
      redirect_with_errors setup_path, farm
    end
  end

  def update
    farm = Current.group.farms.find(params[:id])
    if farm.update(farm_params)
      redirect_to setup_path, notice: "Saved #{farm.name}"
    else
      redirect_with_errors setup_path, farm
    end
  end

  def destroy
    farm = Current.group.farms.find(params[:id])
    farm.destroy!
    redirect_to setup_path, notice: "Deleted #{farm.name}"
  end

  private

  def farm_params = params.expect(farm: [:name, :notes])
end
