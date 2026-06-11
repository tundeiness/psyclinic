class ClientProfileSerializer
  def self.call(cp, include_user: true)
    return nil if cp.nil?

    data = {
      id: cp.id,
      date_of_birth: cp.date_of_birth,
      notes: cp.notes,
      # Phase 12: surface no-show signals so the therapist UI can
      # flag clients who've missed 3 consecutive sessions per the
      # Cerca Africa policy.
      consecutive_no_shows: cp.consecutive_no_shows,
      treatment_review_recommended: cp.treatment_review_recommended?,
      # Phase 14: current_therapist_id lets a therapist UI tell
      # whether this client is currently theirs or a former one.
      # The therapist-side serialization includes this so the
      # client list can show a "Former patient" pill.
      current_therapist_id: cp.current_therapist_id
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
