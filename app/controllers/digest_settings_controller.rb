# The daily digest's settings, on the settings page: on or off, and which fields it covers
class DigestSettingsController < AuthenticatedController
  def update
    settings = params.expect(digest: [:enabled, field_ids: []])
    current_user.transaction do
      current_user.update!(digest: settings[:enabled] == "1")
      current_user.digest_field_ids = settings.fetch(:field_ids, []).compact_blank
    end
    redirect_to settings_path, notice: "Daily email settings saved"
  end
end
