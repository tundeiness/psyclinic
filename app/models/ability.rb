class Ability
  include CanCan::Ability

  def initialize(user)
    return if user.blank?

    case user.role
    when "admin"
      admin_abilities
    when "therapist"
      therapist_abilities(user)
    when "client"
      client_abilities(user)
    end
  end

  private

  # Head-Therapist: full management surface.
  def admin_abilities
    can :manage, User
    can :manage, ClientProfile
    can :manage, TherapistProfile
    can :manage, Specialization
    can :manage, TherapistSpecialization
    # Admin approves/rejects/sees slots but does not author them.
    can %i[read update approve reject], AvailabilitySlot
    can :read, Appointment
  end

  def therapist_abilities(user)
    tp = user.therapist_profile
    return if tp.nil?

    # Clients who have booked an appointment with this therapist
    # (replaces the old admin-assigned pairing).
    can :read, ClientProfile do |client_profile|
      Appointment.where(
        client_profile_id: client_profile.id,
        therapist_profile_id: tp.id
      ).where.not(status: :cancelled).exists?
    end

    # Author and manage their own availability.
    can %i[read create update destroy], AvailabilitySlot, therapist_profile_id: tp.id

    # See and update appointments that belong to them.
    can %i[read update], Appointment, therapist_profile_id: tp.id

    # Therapist-private clinical notes: only for clients who have booked
    # with this therapist, and only their own notes.
    can %i[read create], ClientNote do |note|
      note.therapist_profile_id == tp.id &&
        tp.has_client?(note.client_profile_id)
    end

    can :read, TherapistProfile, id: tp.id
  end

  def client_abilities(user)
    cp = user.client_profile
    return if cp.nil?

    # Browse bookable (approved, free) slots.
    can :read, AvailabilitySlot, status: "approved"

    # Manage only their own appointments.
    can :create, Appointment
    can :read, Appointment, client_profile_id: cp.id
    can :destroy, Appointment, client_profile_id: cp.id, status: %w[booked pending_payment]
  end
end
