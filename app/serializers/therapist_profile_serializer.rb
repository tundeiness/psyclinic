class TherapistProfileSerializer
  def self.call(tp, include_user: true)
    return nil if tp.nil?

    data = {
      id: tp.id,
      bio: tp.bio,
      license_number: tp.license_number,
      active: tp.active,
      specializations: tp.specializations.map { |s| { id: s.id, name: s.name } }
    }
    if include_user
      data[:user] = {
        id: tp.user_id,
        full_name: tp.full_name,
        email: tp.email
      }
    end
    data
  end
end
