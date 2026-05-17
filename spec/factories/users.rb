FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@psyclinic.test" }
    first_name { "Test" }
    last_name { "User" }
    password { "Password123!" }
    password_confirmation { "Password123!" }
    role { :client }
    # Tests generally want usable accounts; approval workflow is exercised
    # explicitly via the :pending trait.
    status { :approved }

    trait :admin do
      role { :admin }
      allow_admin_assignment { true }
      status { :approved }
    end

    trait :therapist do
      role { :therapist }
    end

    trait :client do
      role { :client }
    end

    trait :pending do
      status { :pending }
    end

    trait :rejected do
      status { :rejected }
    end
  end

  factory :specialization do
    sequence(:name) { |n| "Specialization #{n}" }
  end
end
