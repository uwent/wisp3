# The current operation's members (Q8). Owners add people by the email they sign in with (they
# need an account first), change roles and remove members; anyone can leave.
class MembershipsController < AuthenticatedController
  before_action :require_owner, only: [:create, :update]
  # Adding a member emails them in the user's name
  before_action :forbid_while_impersonating, only: :create

  # Anyone with an account owns an operation and can add people to it, which emails them and says
  # whether an address has an account. So the tries one user makes are limited, and the emails
  # to one address (added, removed and added again), from any operation.
  def self.tries_limit(user) = WindowLimit.new("member-adds:#{user.id}", limit: 20, window: 1.hour)
  def self.emails_limit(email) = WindowLimit.new("member-add-emails:#{email}", limit: 3, window: 1.day)

  def create
    email = params.expect(membership: [:email])[:email].to_s.strip.downcase
    user = User.find_by(email:)
    tries, emails = self.class.tries_limit(current_user), self.class.emails_limit(email)
    error =
      if email.blank? then "Enter the email address they use to sign in to WISP."
      elsif !tries.allow! then "You've added several people already. #{tries.retry_message}"
      elsif user.nil? then "No WISP account uses #{email}. Ask them to create one, then add them."
      elsif !user.confirmed? then "#{email} hasn't confirmed their email address yet. Ask them to open the confirmation link, then add them again."
      elsif Current.group.users.include?(user) then "#{user.display_name} is already a member"
      elsif !emails.allow! then "#{user.display_name} has been added to operations several times today. #{emails.retry_message}"
      end
    return redirect_with_errors(group_path, {email: [error]}) if error

    membership = Current.group.memberships.create!(user:, owner: params.dig(:membership, :owner) == "true")
    MembershipMailer.added(membership, current_user).deliver_later
    redirect_to group_path, notice: "Added #{user.display_name}. We've emailed them, and they can switch to " \
      "#{Current.group.name} from the operation menu."
  end

  def update
    membership = Current.group.memberships.find(params[:id])
    owner = params.expect(membership: [:owner])[:owner] == "true"
    if (error = membership.change_role(owner))
      return redirect_to(group_path, alert: error)
    end

    redirect_to group_path, notice: "#{membership.user.display_name} is now #{owner ? "an owner" : "a member"}"
  end

  def destroy
    membership = Current.group.memberships.find(params[:id])
    leaving = membership == Current.membership
    return require_owner unless leaving || Current.owner?
    if (error = membership.remove)
      return redirect_to(group_path, alert: error, status: :see_other)
    end

    if leaving
      session.delete(:group_id)
      redirect_to root_path, notice: "You left #{Current.group.name}", status: :see_other
    else
      redirect_to group_path, notice: "Removed #{membership.user.display_name}", status: :see_other
    end
  end
end
