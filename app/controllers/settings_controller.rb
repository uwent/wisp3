# Profile and display preferences. Email and password changes go through Devise
# (Users::RegistrationsController#update), shown on the same page.
class SettingsController < AuthenticatedController
  def show
    render inertia: "Settings/Show", props: {
      unit_systems: User::UNIT_SYSTEMS,
      pending_email: current_user.pending_reconfirmation? ? current_user.unconfirmed_email : nil
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

  def profile_params
    params.expect(user: [:first_name, :last_name, :unit_system])
  end
end
