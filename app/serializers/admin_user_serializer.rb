# A row of the admin users table. params[:counts] is {user_id => {farms:, pivots:, fields:}}
# over the user's groups.
class AdminUserSerializer < ApplicationSerializer
  typelize_from User

  attributes :id, :email, :admin, :created_at, :current_sign_in_at

  attribute :display_name, &:display_name
  attribute :confirmed, &:confirmed?

  %i[farms pivots fields].each do |kind|
    attribute :"#{kind}_count" do |user|
      params[:counts].dig(user.id, kind) || 0
    end
  end

  typelize display_name: :string, confirmed: :boolean, created_at: :string, current_sign_in_at: "string | null",
    farms_count: :number, pivots_count: :number, fields_count: :number
end
