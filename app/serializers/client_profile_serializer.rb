class ClientProfileSerializer
  def self.call(cp, include_user: true)
    return nil if cp.nil?

    data = {
      id: cp.id,
      date_of_birth: cp.date_of_birth,
      notes: cp.notes
    }
    if include_user
      data[:user] = {
        id: cp.user_id,
        full_name: cp.full_name,
        email: cp.email
      }
    end
    data
  end
end
