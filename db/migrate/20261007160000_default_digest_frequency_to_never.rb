# New accounts start with the digest off; existing users keep their setting.
class DefaultDigestFrequencyToNever < ActiveRecord::Migration[8.1]
  def change
    change_column_default :users, :digest_frequency, from: "daily", to: "never"
  end
end
