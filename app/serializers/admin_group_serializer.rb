# One of a user's groups on the admin user page: its members and its farms, pivots and fields
class AdminGroupSerializer < ApplicationSerializer
  typelize_from Group

  attributes :id, :name, :use_model_precip

  attribute :members do |group|
    group.memberships.sort_by { |membership| membership.user.email }.map do |membership|
      {id: membership.user_id, email: membership.user.email, admin: membership.admin}
    end
  end

  many :farms, proc { |farms| farms.sort_by(&:name) }, resource: FarmSerializer

  typelize members: "{ id: number; email: string; admin: boolean }[]"
end
