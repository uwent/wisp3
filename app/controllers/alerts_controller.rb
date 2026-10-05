# The daily digest's settings (PLAN.md Phase 6): how often it's sent and which fields it covers,
# with a preview of today's email (loaded on request) and a test send, once per cooldown
class AlertsController < AuthenticatedController
  def show
    groups = current_user.groups.order(:name).includes(farms: {pivots: :fields})
    render inertia: "Alerts/Show", props: {
      frequency: current_user.digest_frequency,
      field_ids: current_user.digest_fields.pluck(:id),
      groups: groups.map do |group|
        {id: group.id, name: group.name, farms: group.farms.sort_by(&:name).map do |farm|
          {id: farm.id, name: farm.name,
           fields: farm.pivots.flat_map { |pivot| pivot.fields.map { |field| {id: field.id, name: field.name, pivot: pivot.name} } }}
        end}
      end,
      # Seconds until another test email can be sent
      test_wait: current_user.digest_test_available_at&.then { |at| (at - Time.current).ceil } || 0,
      preview: InertiaRails.optional { DigestMailer.preview(DailyDigest.new(current_user)) }
    }
  end

  def update
    settings = params.expect(digest: [:frequency, field_ids: []])
    current_user.digest_frequency = settings[:frequency]
    return redirect_with_errors(alerts_path, current_user) unless current_user.valid?

    current_user.transaction do
      current_user.save!
      current_user.digest_field_ids = settings.fetch(:field_ids, []).compact_blank
    end
    redirect_to alerts_path, notice: "Alert settings saved"
  end

  # Today's digest, sent now whatever the frequency, so the user can see it in their inbox. The
  # cooldown starts only when something is sent.
  def test_email
    return redirect_to(alerts_path, alert: cooldown_message) if current_user.digest_test_available_at

    if DailyDigest.new(current_user).entries.none?
      redirect_to alerts_path, alert: "There's nothing to send: no included field has a crop in season today."
    elsif current_user.claim_digest_test!
      DigestMailer.test_daily(current_user).deliver_later
      redirect_to alerts_path, notice: "Test email sent to #{current_user.email}"
    else
      redirect_to alerts_path, alert: cooldown_message
    end
  end

  private

  def cooldown_message
    minutes = ((current_user.reload.digest_test_available_at.to_f - Time.current.to_f) / 60).ceil.clamp(1..)
    "You can send another test email in #{minutes} #{"minute".pluralize(minutes)}."
  end
end
