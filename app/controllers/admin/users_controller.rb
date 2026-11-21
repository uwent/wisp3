module Admin
  # Every account, for helping people with their sign-in or farm setup. Admins see all users, so
  # these lookups are deliberately not scoped to Current.group. An admin can delete accounts other
  # than their own and other admins'.
  class UsersController < BaseController
    def index
      users = User.order(created_at: :desc)
      render inertia: "Admin/Users/Index", props: {
        users: AdminUserSerializer.new(users, params: {stats: AdminUserStats.new}).serializable_hash
      }
    end

    def export
      csv = AdminUsersCsv.new(User.order(:id).to_a, AdminUserStats.new, exported_by: current_user, about_url:).to_csv
      send_csv csv, "wisp-accounts-#{Current.today.iso8601}.csv"
    end

    def show
      user = User.find(params[:id])
      groups = user.groups.order(:name)
        .includes(memberships: :user, farms: [:pivot_groups, {pivots: {fields: [:soil_type, {plantings: [:plant, :canopy_cuttings]}]}}])
      render inertia: "Admin/Users/Show", props: {
        user: AdminUserDetailSerializer.new(user).serializable_hash,
        groups: AdminGroupSerializer.new(groups).serializable_hash,
        deletable: deletable?(user),
        # Signing in as the user (Admin::ImpersonationsController) has the same limits as deleting
        impersonatable: deletable?(user)
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
  end
end
