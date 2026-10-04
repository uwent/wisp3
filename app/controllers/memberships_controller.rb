# The current operation's members (Q8). Owners add people by the email they sign in with (they
# need an account first), change roles and remove members; anyone can leave.
class MembershipsController < AuthenticatedController
  before_action :require_owner, only: [:create, :update]

  def create
    email = params.expect(membership: [:email])[:email].to_s.strip.downcase
    user = User.find_by(email:)
    error =
      if email.blank? then "Enter the email they sign in with"
      elsif user.nil? then "No WISP account uses #{email}. Ask them to create one, then add them."
      elsif !user.confirmed? then "#{email} hasn't confirmed their account yet"
      elsif Current.group.users.include?(user) then "#{user.display_name} is already a member"
      end
    return redirect_with_errors(group_path, {email: [error]}) if error

    membership = Current.group.memberships.create!(user:, owner: params.dig(:membership, :owner) == "true")
    MembershipMailer.added(membership, current_user).deliver_later
    redirect_to group_path, notice: "Added #{user.display_name}. They'll get an email, and can switch to #{Current.group.name} from the menu."
  end

  def update
    membership = Current.group.memberships.find(params[:id])
    owner = params.expect(membership: [:owner])[:owner] == "true"
    error = membership.demotion_error unless owner
    return redirect_to(group_path, alert: error) if error

    membership.update!(owner:)
    redirect_to group_path, notice: "#{membership.user.display_name} is now #{owner ? "an owner" : "a member"}"
  end

  def destroy
    membership = Current.group.memberships.find(params[:id])
    leaving = membership == Current.membership
    return require_owner unless leaving || Current.owner?
    if (error = membership.removal_error)
      return redirect_to(group_path, alert: error, status: :see_other)
    end

    membership.destroy!
    if leaving
      session.delete(:group_id)
      redirect_to root_path, notice: "You left #{Current.group.name}", status: :see_other
    else
      redirect_to group_path, notice: "Removed #{membership.user.display_name}", status: :see_other
    end
  end
end
