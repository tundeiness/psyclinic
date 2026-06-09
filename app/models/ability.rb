class Ability
  include CanCan::Ability

  def initialize(user)
    return if user.blank?

    # Co-admin is a therapist with elevated powers — check before the
    # role switch so they get the management surface, plus their normal
    # therapist abilities.
    if user.co_admin?
      co_admin_abilities(user)
      therapist_abilities(user)
      return
    end

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

  # Co-admin: can manage clients, therapists and applications, but
  # CANNOT manage admins or promote/remove co-admins (those are guarded
  # in the controllers as admin-only). Co-admins are never role: admin.
  def co_admin_abilities(_user)
    can :access, :admin_panel
    can :manage, ClientProfile
    can :manage, TherapistProfile
    can :read, Appointment
    can %i[read update approve reject], AvailabilitySlot
    # Review/approve client & therapist applications, but not admins.
    can %i[read update], User, role: %w[client therapist]
    # Co-admin can also moderate blog posts.
    can :manage, BlogPost
    # Co-admin has clinical oversight: can read all EMR records,
    # but only write/update for clients they've personally had a
    # session with. Mirrors how a clinical director might supervise
    # while still respecting authorship boundaries for new records.
    can :read, IntakeForm
    can :read, SessionNote
    can :read, ServicePlanNote
    can :read, DassAssessment
    can :read, WheelOfLifeAssessment
  end

  # Head-Therapist: full management surface.
  def admin_abilities
    can :access, :admin_panel
    can :manage, User
    can :manage, ClientProfile
    can :manage, TherapistProfile
    can :manage, Specialization
    can :manage, TherapistSpecialization
    # Admin approves/rejects/sees slots but does not author them.
    can %i[read update approve reject], AvailabilitySlot
    can :read, Appointment
    # Blog moderation: admin can read/edit/delete any post.
    can :manage, BlogPost
    # EMR: admin is a clinical role (head therapist). Full manage —
    # but signed records still become read-only via the Signable
    # concern at the model layer, regardless of role.
    can :manage, IntakeForm
    can :manage, SessionNote
    can :manage, ServicePlanNote
    can :manage, DassAssessment
    can :manage, WheelOfLifeAssessment
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

    # EMR forms — v2 authorization model.
    #
    # For therapist-authored records (intake, session note, service
    # plan): the CURRENT treating therapist can read/create/update.
    # Former therapists (who once treated this client but the client
    # has since switched) retain READ access to records they
    # themselves authored — they cannot create new records or edit
    # existing ones. The Signable concern still locks signed records
    # at the model layer regardless of role.
    #
    # For client-authored records (DASS, Wheel of Life): only the
    # current therapist can read. Former therapists do not see
    # assessments the client has submitted, including those submitted
    # while they were the current therapist — once the relationship
    # ends, that data goes with the client. (A future record-release
    # flow lets admins grant explicit access; not yet built.)
    #
    # "Current treating therapist" = client_profile.current_therapist_id
    # equals this therapist's id. Null current_therapist_id means the
    # client has no current therapist — no therapist has access until
    # one is assigned (via the booking flow, later phase).
    is_current_therapist = ->(client_profile_id) {
      cp = ClientProfile.find_by(id: client_profile_id)
      cp&.current_therapist_id == tp.id
    }

    # Therapist-authored records: write only if current; read if
    # current OR if author.
    %i[IntakeForm SessionNote ServicePlanNote].each do |klass_sym|
      klass = klass_sym.to_s.constantize
      can %i[create update], klass do |record|
        is_current_therapist.call(record.client_profile_id)
      end
      can :read, klass do |record|
        is_current_therapist.call(record.client_profile_id) ||
          record.author_id == user.id
      end
    end

    # Client-authored records: current therapist reads only.
    can :read, DassAssessment do |record|
      is_current_therapist.call(record.client_profile_id)
    end
    can :read, WheelOfLifeAssessment do |record|
      is_current_therapist.call(record.client_profile_id)
    end

    can :read, TherapistProfile, id: tp.id

    # Therapist authors blog posts. They can create new ones, and
    # read/update/destroy their own.
    can :create, BlogPost
    can %i[read update destroy], BlogPost, author_id: user.id
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

    # EMR — v2: client fills their own DASS-42 and Wheel of Life on
    # their dashboard when asked. No signature; submission = locked.
    # No client access to therapist-authored records (intake, session
    # note, service plan).
    can %i[create read], DassAssessment, client_profile_id: cp.id
    can %i[create read], WheelOfLifeAssessment, client_profile_id: cp.id

    # v2 block purchasing — clients buy 6-session blocks for use
    # with their current therapist. They can see their own blocks
    # but never another client's.
    can :create, SessionBlock
    can :read,   SessionBlock, client_profile_id: cp.id
  end
end
