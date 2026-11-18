# Records the day and the part of WISP each signed-in request used (ActivityDay, PLAN.md H.2). The
# session remembers what's been recorded today, so the table is written once per area per day,
# not on every request. Admins, an admin signed in as someone else and the example farm aren't
# recorded. The real date, not Current.today: time travel is an admin's tool.
module RecordsActivity
  extend ActiveSupport::Concern

  SESSION_KEY = :activity

  included do
    after_action :record_activity
  end

  private

  def record_activity
    return unless current_user && !current_user.admin? && !impersonator && !example_group
    return unless response.successful? || response.redirect?

    area = ActivityDay.area_for(controller_path, action_name, csv: request.format.csv?)
    return unless area

    today = Date.current.iso8601
    phone = request.user_agent.to_s.include?("Mobi")
    seen = session[SESSION_KEY]
    seen = {"on" => today, "areas" => [], "phone" => false} unless seen.is_a?(Hash) && seen["on"] == today
    return if seen["areas"].include?(area) && (seen["phone"] || !phone)

    ActivityDay.record(current_user, date: Date.current, area:, phone:)
    session[SESSION_KEY] = seen.merge("areas" => seen["areas"] | [area], "phone" => seen["phone"] || phone)
  end
end
