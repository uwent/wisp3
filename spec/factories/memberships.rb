FactoryBot.define do
  factory :membership do
    user
    group
    owner { false }
  end
end
