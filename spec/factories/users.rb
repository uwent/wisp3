FactoryBot.define do
  factory :user do
    first_name { "Pat" }
    last_name { "Grower" }
    sequence(:email) { |n| "grower#{n}@example.com" }
    password { "correct horse battery" }
    confirmed_at { Time.current }

    trait :unconfirmed do
      confirmed_at { nil }
    end
  end
end
