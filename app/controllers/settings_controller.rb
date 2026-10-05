# Profile and display preferences. Email and password changes go through Devise
# (Users::RegistrationsController#update), shown on the same page.
class SettingsController < AuthenticatedController
  def show
    render inertia: "Settings/Show", props: {
      unit_systems: User::UNIT_SYSTEMS,
      pending_email: current_user.pending_reconfirmation? ? current_user.unconfirmed_email : nil,
      digest: digest_props
    }
  end

  def update
    if current_user.update(profile_params)
      redirect_to settings_path, notice: "Settings saved"
    else
      redirect_with_errors settings_path, current_user
    end
  end

  private

  # The daily digest's switch, and every field in the user's operations by farm, with those it covers
  def digest_props
    groups = current_user.groups.order(:name).includes(farms: {pivots: :fields})
    {
      enabled: current_user.digest?,
      field_ids: current_user.digest_fields.pluck(:id),
      groups: groups.map do |group|
        {id: group.id, name: group.name, farms: group.farms.sort_by(&:name).map do |farm|
          {id: farm.id, name: farm.name,
           fields: farm.pivots.flat_map { |pivot| pivot.fields.map { |field| {id: field.id, name: field.name, pivot: pivot.name} } }}
        end}
      end
    }
  end

  def profile_params
    params.expect(user: [:first_name, :last_name, :unit_system])
  end
end
