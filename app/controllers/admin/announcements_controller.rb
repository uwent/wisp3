module Admin
  # Announcements by email to an audience of accounts (Announcement): drafts composed in Markdown
  # with a live preview, a test sent to the admin, then sent by AnnouncementJob, with its progress
  # and any failures on the announcement's page. Only drafts can be edited or deleted.
  class AnnouncementsController < BaseController
    before_action :set_announcement, only: [:show, :edit, :update, :destroy, :test, :deliver, :resume]
    before_action :require_draft, only: [:edit, :update, :destroy, :deliver]

    def index
      announcements = Announcement.order(Arel.sql("sent_at DESC NULLS FIRST"), created_at: :desc)
      render inertia: "Admin/Announcements/Index", props: {
        announcements: AdminAnnouncementSerializer.new(announcements).serializable_hash
      }
    end

    def new
      render_form Announcement.new(audience: "all")
    end

    def create
      announcement = Announcement.new(announcement_params.merge(created_by: current_user))
      if announcement.save
        redirect_to admin_announcement_path(announcement), notice: "Draft saved", status: :see_other
      else
        redirect_with_errors new_admin_announcement_path, announcement
      end
    end

    def show
      progress = @announcement.draft? ? nil : @announcement.progress
      render inertia: "Admin/Announcements/Show", props: {
        announcement: AdminAnnouncementSerializer.new(@announcement).serializable_hash,
        # The email as the admin would get it, with their own name in the placeholders
        preview: AnnouncementMailer.preview(@announcement, current_user),
        recipients_now: @announcement.draft? ? @announcement.recipients.count : nil,
        progress:,
        failures: @announcement.deliveries.where(status: "failed").includes(:user).order(:id).limit(50)
          .map { |delivery| {email: delivery.user.email, error: delivery.error} }
      }
    end

    def edit
      render_form @announcement
    end

    def update
      if @announcement.update(announcement_params)
        redirect_to admin_announcement_path(@announcement), notice: "Draft saved", status: :see_other
      else
        redirect_with_errors edit_admin_announcement_path(@announcement), @announcement
      end
    end

    def destroy
      @announcement.destroy!
      redirect_to admin_announcements_path, notice: "Draft deleted", status: :see_other
    end

    # The composer's preview of the email being written, as JSON: {subject:, html:, errors:}
    def preview
      announcement = Announcement.new(announcement_params)
      announcement.subject = "(No subject)" if announcement.subject.blank?
      announcement.validate
      response.headers["Cache-Control"] = "no-store"
      render json: AnnouncementMailer.preview(announcement, current_user)
        .merge(errors: announcement.errors.full_messages_for(:body))
    end

    # The saved announcement to the admin alone
    def test
      AnnouncementMailer.announcement(@announcement, current_user, test: true).deliver_now
      redirect_to admin_announcement_path(@announcement), notice: "Test sent to #{current_user.email}", status: :see_other
    end

    def deliver
      if @announcement.send!(by: current_user)
        redirect_to admin_announcement_path(@announcement),
          notice: "Sending to #{helpers.pluralize(@announcement.recipients_count, "person")}", status: :see_other
      else
        redirect_to admin_announcement_path(@announcement), alert: "No one in that audience can be sent it.",
          status: :see_other
      end
    end

    def resume
      if @announcement.resume!
        redirect_to admin_announcement_path(@announcement), notice: "Sending again to those it missed", status: :see_other
      else
        redirect_to admin_announcement_path(@announcement), alert: "It's still sending.", status: :see_other
      end
    end

    private

    def set_announcement
      @announcement = Announcement.find(params[:id])
    end

    def require_draft
      return if @announcement.draft?

      redirect_to admin_announcement_path(@announcement), alert: "It's been sent, so it can't be changed.",
        status: :see_other
    end

    def announcement_params
      params.expect(announcement: [:subject, :body, :audience, :audience_date])
    end

    def render_form(announcement)
      date = parse_date(params[:date]) || announcement.audience_date || season_start
      render inertia: "Admin/Announcements/Form", props: {
        announcement: announcement.persisted? ? AdminAnnouncementSerializer.new(announcement).serializable_hash : nil,
        audience_date: date.iso8601,
        # Each audience's count for the date, refreshed (only: audiences) as the date changes
        audiences: Announcement::AUDIENCES.map do |key, audience|
          audience.merge(key:, count: Announcement.recipients_for(key, date).count)
        end,
        placeholders: Announcement::PLACEHOLDERS.map { |key, placeholder| {key:, description: placeholder[:description]} }
      }
    end

    # March 1 of this season, or last season's before March: when "active since" usually begins
    def season_start
      today = Current.today
      march = Date.new(today.year, 3, 1)
      (today < march) ? march.prev_year : march
    end
  end
end
