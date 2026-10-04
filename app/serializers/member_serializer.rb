# A member of the current operation, on its page
class MemberSerializer < ApplicationSerializer
  typelize_from Membership

  attributes :id, :user_id, :owner, :created_at

  attribute :name do |membership|
    membership.user.name.presence
  end

  attribute :email do |membership|
    membership.user.email
  end

  typelize name: "string | null", email: :string, created_at: :string
end
