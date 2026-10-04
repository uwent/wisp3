# The current farm operation (a group, Q8): its settings, members and deletion, and creating
# another. Members see the page; owners change it.
class GroupsController < AuthenticatedController
  before_action :require_owner, only: [:update, :destroy]

  def show
    group = Current.group
    operations = current_user.memberships.includes(group: :memberships).sort_by { |membership| membership.group.name.downcase }
    render inertia: "Groups/Show", props: {
      members: MemberSerializer.new(group.memberships.includes(:user).order(:created_at, :id)).to_h,
      membership_id: Current.membership.id,
      counts: {farms: group.farms.count, pivots: group.pivots.count, fields: group.fields.count},
      operations: operations.map do |membership|
        {id: membership.group_id, name: membership.group.name, owner: membership.owner, members: membership.group.memberships.size}
      end
    }
  end

  def create
    group = Group.new(params.expect(group: [:name]))
    if group.save
      group.memberships.create!(user: current_user, owner: true)
      session[:group_id] = group.id
      redirect_to group_path, notice: "Created #{group.name}. It's now the operation you're working in."
    else
      redirect_with_errors group_path, group
    end
  end

  def update
    if Current.group.update(params.expect(group: [:name, :use_model_precip]))
      redirect_to group_path, notice: "Saved"
    else
      redirect_with_errors group_path, Current.group
    end
  end

  def destroy
    Current.group.destroy!
    session.delete(:group_id)
    redirect_to root_path, notice: "Deleted #{Current.group.name}", status: :see_other
  end
end
