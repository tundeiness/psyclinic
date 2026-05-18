module Serializers
end

class UserSerializer
  def self.call(user)
    base = {
      id: user.id,
      email: user.email,
      first_name: user.first_name,
      last_name: user.last_name,
      full_name: user.full_name,
      phone: user.phone,
      role: user.role,
      status: user.status,
      avatar: AttachmentSerializer.one(user.avatar),
      documents: AttachmentSerializer.many(user.documents),
      created_at: user.created_at
    }

    case user.role
    when "therapist"
      base[:therapist_profile] = TherapistProfileSerializer.call(user.therapist_profile) if user.therapist_profile
    when "client"
      base[:client_profile] = ClientProfileSerializer.call(user.client_profile) if user.client_profile
    end

    base
  end
end
