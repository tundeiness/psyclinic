class TherapistProfile < ApplicationRecord
  belongs_to :user

  has_many :availability_slots, dependent: :destroy
  has_many :appointments, dependent: :destroy

  # v2: blocks of 6 sessions sold to clients for use with this
  # therapist. Restrict-on-delete (via the FK) keeps a therapist
  # with active blocks from being soft-deleted accidentally.
  has_many :session_blocks, dependent: :restrict_with_exception

  has_many :therapist_specializations, dependent: :destroy
  has_many :specializations, through: :therapist_specializations

  # Therapists author EMR records via the `author` association on
  # each form (see Signable). No direct has_many here — a therapist
  # may author records for any client they have a session with, not a
  # bounded set.

  scope :active, -> { where(active: true) }

  delegate :full_name, :email, to: :user

  # Clients who have at least one (non-cancelled) appointment with this
  # therapist. Replaces the old admin-assigned pairing.
  # Clients who have booked at least one non-cancelled appointment
  # with this therapist, OR for whom this therapist appears in the
  # ClientTherapistAssignment history (as the current or former
  # therapist). Former patients remain visible so the therapist can
  # access records they authored — per Cerca Africa's policy and
  # the Phase 14 design.
  #
  # The assignment-history part matters specifically when a client
  # cancels their last pending appointment with the therapist as a
  # precondition for switching: without this OR clause, the client
  # would vanish from the prior therapist's list the moment they
  # switched, breaking the "retain read access to records I authored"
  # guarantee.
  def clients_with_appointments
    from_appointments = ClientProfile
      .joins(:appointments)
      .where(appointments: { therapist_profile_id: id })
      .where.not(appointments: { status: :cancelled })

    from_assignments = ClientProfile
      .joins(:therapist_assignments)
      .where(
        "client_therapist_assignments.from_therapist_id = :id " \
        "OR client_therapist_assignments.to_therapist_id = :id",
        id: id
      )

    # Union via two-step query — Postgres supports proper UNION but
    # ActiveRecord doesn't compose UNION naturally across scopes,
    # so we collect IDs and re-query for a stable relation.
    ids = (from_appointments.pluck(:id) + from_assignments.pluck(:id)).uniq
    ClientProfile.where(id: ids)
  end

  # True if the given client has booked (non-cancelled) with this
  # therapist. Single source of truth for "may this therapist see /
  # note this client" — reused by Ability and controllers.
  def has_client?(client_profile_id)
    Appointment
      .where(client_profile_id: client_profile_id, therapist_profile_id: id)
      .where.not(status: :cancelled)
      .exists?
  end
end
