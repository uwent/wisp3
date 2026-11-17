# Base for every signed-in page. Sets Current.group from the session, but only ever to a
# group the user is a member of, so every group-scoped query starts from a group they own. In
# example mode (ExampleMode, PLAN.md G.8) it's the example farm instead, for anyone, signed in or
# not, and only on the actions a controller allows with allow_example, which only read.
class AuthenticatedController < InertiaController
  before_action :authenticate_user!, unless: :example_group
  before_action :set_current_group

  # The read-only actions example mode may show (GET only)
  class_attribute :example_actions, instance_writer: false, default: [].freeze

  def self.allow_example(*actions) = self.example_actions = actions.map(&:to_s).freeze

  private

  def set_current_group
    return enter_example if example_group

    Current.user = current_user
    memberships = current_user.memberships.includes(:group)
    # Someone removed from their last group gets a fresh one of their own
    current_user.create_personal_group if memberships.none?
    # Links from emails name the record's group (?operation=), which may not be the current one
    Current.membership = memberships.find_by(group_id: params[:operation]) if params[:operation].is_a?(String)
    Current.membership ||= memberships.find_by(group_id: session[:group_id]) || memberships.order(:group_id).first
    Current.group = Current.membership.group
    session[:group_id] = Current.group.id
  end

  # The example farm, as of its day, on the pages it may show; anything else (other pages, any
  # write) goes back to its dashboard. Never a membership: no one owns it here.
  def enter_example
    unless request.get? && example_actions.include?(action_name)
      message = current_user ? "The example farm can only be viewed. Leave it (in the bar at the top) to use your own." :
        "The example farm can only be viewed. Create an account to set up your own."
      return redirect_to root_path, alert: message, status: :see_other
    end
    limit = ExampleMode.limit(request.remote_ip)
    return render plain: "Too many requests. #{limit.retry_message}", status: :too_many_requests unless limit.allow!

    Current.user = current_user
    Current.group = example_group
    Current.as_of = example_group.example_as_of
  end

  # ?year=, a season from 2000 to next year; anything else (missing, malformed, out of range) the
  # current one
  def requested_year
    today = Current.today
    year = params[:year].to_s.to_i
    year.between?(2000, today.year + 1) ? year : today.year
  end

  # For actions only the group's owners may take (Q8)
  def require_owner
    return if Current.owner?

    redirect_back_or_to root_path, alert: "Only an owner of #{Current.group.name} can do that.", status: :see_other
  end

  # Deleting a planting or an irrigation group: its group's owners, or the member who created it
  # (G.15). False after redirecting, so the action returns.
  def owner_or_creator?(record)
    return true if Current.owner? || (record.created_by_id && record.created_by_id == Current.user.id)

    redirect_back_or_to root_path, alert: "Only an owner of #{Current.group.name} or the person who added it can delete it.",
      status: :see_other
    false
  end
end
