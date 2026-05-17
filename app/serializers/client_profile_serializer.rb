class ClientProfileSerializer
  def self.call(cp, include_user: true)
    return nil if cp.nil?

    data = {
      id: cp.id,
      date_of_birth: cp.date_of_birth,
      notes: cp.notes,
      paired: cp.paired?,
      therapist_profile_id: cp.therapist_profile_id
    }
    if include_user
      data[:user] = {
        id: cp.user_id,
        full_name: cp.full_name,
        email: cp.email
      }
    end
    if cp.therapist_profile
      data[:therapist] = {
        id: cp.therapist_profile.id,
        full_name: cp.therapist_profile.full_name
      }
    end
    data
  end
end
