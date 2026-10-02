class UserSerializer < ApplicationSerializer
  attributes :id, :email, :first_name, :last_name, :admin, :unit_system

  attribute :display_name do |user|
    user.display_name
  end
  typelize display_name: :string, unit_system: "'imperial' | 'metric'"
end
