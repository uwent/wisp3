module Admin
  # Every account, for helping people with their sign-in or farm setup. Admins see all users, so
  # these lookups are deliberately not scoped to Current.group. An admin can delete accounts other
  # than their own and other admins'.
  class UsersController < BaseController
    def index
      users = User.order(created_at: :desc)
      render inertia: "Admin/Users/Index", props: {
        users: AdminUserSerializer.new(users, params: {counts: setup_counts}).serializable_hash
      }
    end

    def show
      user = User.find(params[:id])
      groups = user.groups.order(:name)
        .includes(memberships: :user, farms: {pivots: {fields: [:soil_type, {plantings: :plant}]}})
      render inertia: "Admin/Users/Show", props: {
        user: AdminUserDetailSerializer.new(user).serializable_hash,
        groups: AdminGroupSerializer.new(groups).serializable_hash,
        deletable: deletable?(user)
      }
    end

    # What the daily digest would send this user today (PLAN.md Phase 6), without sending it
    def digest
      user = User.find(params[:id])
      render inertia: "Admin/Users/Digest", props: {
        user: {id: user.id, email: user.email},
        preview: DigestMailer.preview(DailyDigest.new(user))
      }
    end

    def destroy
      user = User.find(params[:id])
      unless deletable?(user)
        return redirect_to admin_user_path(user), alert: "You can't delete your own account or another admin's here.",
          status: :see_other
      end

      user.destroy!
      redirect_to admin_users_path, notice: "Deleted #{user.email}.", status: :see_other
    end

    private

    def deletable?(user) = user != current_user && !user.admin?

    # {user_id => {farms:, pivots:, fields:}} over every group each user belongs to
    def setup_counts
      farms = Farm.group(:group_id).count
      pivots = Pivot.joins(:farm).group("farms.group_id").count
      fields = Field.joins(pivot: :farm).group("farms.group_id").count
      Membership.pluck(:user_id, :group_id).each_with_object({}) do |(user_id, group_id), counts|
        totals = counts[user_id] ||= {farms: 0, pivots: 0, fields: 0}
        totals[:farms] += farms.fetch(group_id, 0)
        totals[:pivots] += pivots.fetch(group_id, 0)
        totals[:fields] += fields.fetch(group_id, 0)
      end
    end
  end
end
