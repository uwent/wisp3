# A row of the admin users table. params[:stats] is an AdminUserStats: counts over the user's
# groups and when they were last active.
class AdminUserSerializer < ApplicationSerializer
  typelize_from User

  attributes :id, :email, :admin, :created_at, :current_sign_in_at

  attribute :display_name, &:display_name
  attribute :confirmed, &:confirmed?

  %i[farms pivots fields plantings_season].each do |kind|
    attribute :"#{kind}_count" do |user|
      params[:stats][user.id][kind]
    end
  end

  attribute :last_active_on do |user|
    params[:stats][user.id].last_active_on&.iso8601
  end

  typelize display_name: :string, confirmed: :boolean, created_at: :string, current_sign_in_at: "string | null",
    farms_count: :number, pivots_count: :number, fields_count: :number, plantings_season_count: :number,
    last_active_on: "string | null"
end
