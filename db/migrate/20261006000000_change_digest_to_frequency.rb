# Phase 6: the digest's on/off switch becomes how often it's sent (never, daily during the season,
# or only on days a field needs irrigation soon), and a test email can be sent from the Alerts page
# once per cooldown.
class ChangeDigestToFrequency < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :digest_frequency, :string, default: "daily", null: false
    add_check_constraint :users, "digest_frequency IN ('never', 'daily', 'needed')", name: "users_digest_frequency"
    execute "UPDATE users SET digest_frequency = 'never' WHERE NOT digest"
    remove_column :users, :digest
    add_column :users, :digest_test_sent_at, :datetime
  end

  def down
    add_column :users, :digest, :boolean, default: true, null: false
    execute "UPDATE users SET digest = false WHERE digest_frequency = 'never'"
    remove_check_constraint :users, name: "users_digest_frequency"
    remove_column :users, :digest_frequency
    remove_column :users, :digest_test_sent_at
  end
end
