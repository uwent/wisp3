FactoryBot.define do
  factory :membership do
    user
    group
    admin { false }
  end
end
