# Admin announcements by email (PLAN.md Phase 9): a draft composed in Markdown, sent to an audience
# of accounts; each recipient's delivery recorded, so a resumed send reaches only those it missed.
# users.announcements is the account's own unsubscribe, separate from the daily digest's setting.
class CreateAnnouncements < ActiveRecord::Migration[8.1]
  def change
    create_table :announcements do |t|
      t.string :subject, null: false
      t.text :body, null: false
      t.string :audience, null: false, default: "all"
      t.date :audience_date
      t.string :status, null: false, default: "draft"
      t.references :created_by, foreign_key: {to_table: :users, on_delete: :nullify}
      t.references :sent_by, foreign_key: {to_table: :users, on_delete: :nullify}
      t.datetime :sent_at
      t.integer :recipients_count
      t.timestamps

      t.check_constraint "status IN ('draft', 'sending', 'sent', 'incomplete')", name: "announcements_status"
      t.check_constraint "audience IN ('all', 'active_since', 'joined_since', 'no_farms')", name: "announcements_audience"
    end

    create_table :announcement_deliveries do |t|
      t.references :announcement, null: false, foreign_key: {on_delete: :cascade}, index: false
      t.references :user, null: false, foreign_key: {on_delete: :cascade}
      t.string :status, null: false, default: "pending"
      t.string :error
      t.datetime :sent_at
      t.timestamps

      t.index [:announcement_id, :user_id], unique: true
      t.index [:announcement_id, :status]
      t.check_constraint "status IN ('pending', 'sending', 'sent', 'failed', 'skipped')", name: "announcement_deliveries_status"
    end

    add_column :users, :announcements, :boolean, null: false, default: true
  end
end
