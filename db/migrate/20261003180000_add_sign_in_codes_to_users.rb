class AddSignInCodesToUsers < ActiveRecord::Migration[8.1]
  def change
    # The six-digit code emailed with each sign-in link; only an HMAC of it is stored
    add_column :users, :sign_in_code_digest, :string
    add_column :users, :sign_in_code_sent_at, :datetime
    add_column :users, :sign_in_code_attempts, :integer, null: false, default: 0
  end
end
