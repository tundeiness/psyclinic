FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@psyclinic.test" }
    first_name { "Test" }
    last_name { "User" }
    password { "Password123!" }
    password_confirmation { "Password123!" }
    role { :client }

    trait :admin do
      role { :admin }
      allow_admin_assignment { true }
    end

    trait :therapist do
      role { :therapist }
    end

    trait :client do
      role { :client }
    end
  end

  factory :specialization do
    sequence(:name) { |n| "Specialization #{n}" }
  end
end
