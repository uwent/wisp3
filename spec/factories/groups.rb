FactoryBot.define do
  factory :group do
    sequence(:name) { |n| "Farm operation #{n}" }
  end
end
