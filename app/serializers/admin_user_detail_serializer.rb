# An account's details for the admin user page: everything but its secrets (password, tokens,
# sign-in code)
class AdminUserDetailSerializer < ApplicationSerializer
  typelize_from User

  attributes :id, :email, :first_name, :last_name, :unit_system, :admin, :unconfirmed_email, :sign_in_count,
    :created_at, :updated_at, :confirmed_at, :confirmation_sent_at, :current_sign_in_at, :last_sign_in_at,
    :current_sign_in_ip, :last_sign_in_ip, :remember_created_at, :reset_password_sent_at

  attribute :display_name, &:display_name

  typelize display_name: :string, unit_system: "'imperial' | 'metric'", created_at: :string, updated_at: :string,
    confirmed_at: "string | null", confirmation_sent_at: "string | null", current_sign_in_at: "string | null",
    last_sign_in_at: "string | null", remember_created_at: "string | null", reset_password_sent_at: "string | null"
end
