# The daily digest (PLAN.md Phase 6): "daily_all_year" sends every morning even with nothing in
# season (weather for the included pivots); digest_scope chooses which included fields it lists.
class AddDigestScopeAndAllYear < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :users, name: "users_digest_frequency"
    add_check_constraint :users, "digest_frequency IN ('never', 'daily', 'daily_all_year', 'needed')",
      name: "users_digest_frequency"
    add_column :users, :digest_scope, :string, null: false, default: "in_season"
    add_check_constraint :users, "digest_scope IN ('all', 'in_season', 'needs_action', 'needs_irrigation')",
      name: "users_digest_scope"
  end

  def down
    remove_check_constraint :users, name: "users_digest_scope"
    remove_column :users, :digest_scope
    execute "UPDATE users SET digest_frequency = 'daily' WHERE digest_frequency = 'daily_all_year'"
    remove_check_constraint :users, name: "users_digest_frequency"
    add_check_constraint :users, "digest_frequency IN ('never', 'daily', 'needed')", name: "users_digest_frequency"
  end
end
