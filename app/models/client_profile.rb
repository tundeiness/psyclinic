class ClientProfile < ApplicationRecord
  belongs_to :user

  has_many :appointments, dependent: :destroy

  delegate :full_name, :email, to: :user
end
