# Idempotent seeds. Safe to run multiple times.

puts "Seeding..."

admin = User.find_or_initialize_by(email: "admin@psyclinic.test")
if admin.new_record?
  admin.assign_attributes(
    first_name: "Head",
    last_name: "Therapist",
    role: :admin,
    allow_admin_assignment: true,
    password: "Password123!",
    password_confirmation: "Password123!"
  )
  admin.save!
  puts "  created admin -> admin@psyclinic.test / Password123!"
else
  puts "  admin already exists"
end

%w[Anxiety Depression Trauma\ /\ PTSD Family\ Therapy Addiction].each do |name|
  Specialization.find_or_create_by!(name: name)
end
puts "  specializations ensured (#{Specialization.count})"

therapist = User.find_or_initialize_by(email: "therapist@psyclinic.test")
if therapist.new_record?
  therapist.assign_attributes(
    first_name: "Jane",
    last_name: "Doe",
    role: :therapist,
    status: :approved,
    password: "Password123!",
    password_confirmation: "Password123!"
  )
  therapist.save!
  therapist.therapist_profile.update!(
    bio: "Clinical psychologist.",
    license_number: "LIC-1001",
    headline: "Compassionate, evidence-based therapy",
    years_experience: 8,
    hourly_rate_cents: 12_000
  )
  spec = Specialization.find_by(name: "Anxiety")
  TherapistSpecialization.find_or_create_by!(
    therapist_profile: therapist.therapist_profile,
    specialization: spec
  )
  puts "  created therapist -> therapist@psyclinic.test / Password123!"
else
  puts "  therapist already exists"
end

# A second therapist for QA — makes it possible to exercise Phase 14
# (therapist switching) without manually crafting one in rails console.
# Different specialization + headline so they're clearly distinct from
# Jane in the directory.
therapist2 = User.find_or_initialize_by(email: "therapist2@psyclinic.test")
if therapist2.new_record?
  therapist2.assign_attributes(
    first_name: "Ade",
    last_name: "Okafor",
    role: :therapist,
    status: :approved,
    password: "Password123!",
    password_confirmation: "Password123!"
  )
  therapist2.save!
  therapist2.therapist_profile.update!(
    bio: "Clinical psychologist focused on cognitive behavioural therapy " \
         "for trauma and complex grief.",
    license_number: "LIC-1002",
    headline: "Trauma-informed CBT",
    years_experience: 12
  )
  spec_trauma = Specialization.find_by(name: "Trauma / PTSD")
  TherapistSpecialization.find_or_create_by!(
    therapist_profile: therapist2.therapist_profile,
    specialization: spec_trauma
  ) if spec_trauma
  puts "  created therapist 2 -> therapist2@psyclinic.test / Password123!"
else
  puts "  therapist 2 already exists"
end

client = User.find_or_initialize_by(email: "client@psyclinic.test")
if client.new_record?
  client.assign_attributes(
    first_name: "John",
    last_name: "Smith",
    role: :client,
    status: :approved,
    password: "Password123!",
    password_confirmation: "Password123!"
  )
  client.save!
  puts "  created client -> client@psyclinic.test / Password123!"
else
  puts "  client already exists"
end

# NOTE: We deliberately do NOT pin a current_therapist on John in
# the seed. An earlier version did so as a "v2 dev convenience" but
# that produced an internally-inconsistent state: a client bound to
# a therapist without ever having paid for an assessment with them
# (which is impossible in production). The demo paid appointment
# below now uses session_kind: :assessment, so ConfirmPayment sets
# current_therapist_id naturally — same end state, real flow.

# Phase 15 dev convenience: pre-sign John's services contract so a
# fresh `db:seed` lands him past the contract gate. Without this
# every reset puts him into "Sign your contract" state and the
# downstream QA flows (booking, EMR PDF download, switching) all
# require the user to click through /contract first. The signing
# service requires that the typed name match the user's actual
# first + last name; we feed the right value to satisfy that check.
if client.client_profile &&
   client.client_profile.client_contracts.none?(&:valid_for_use?)
  begin
    SignClientContract.call(
      client_profile: client.client_profile,
      typed_name: client.full_name,
      signed_from_ip: "127.0.0.1"
    )
    puts "  signed services contract for John (dev seed)"
  rescue => e
    # Never block the rest of the seed on this convenience step —
    # if signing fails for any reason (e.g., service-side rule
    # change), log and continue. The user can still sign through
    # the UI.
    puts "  could not pre-sign John's contract (#{e.class}): #{e.message}"
  end
end

# Demo data: one approved slot ~36h out, plus a paid, booked appointment
# on it — so the admin dashboard shows inflows/calendar and the reminder
# task has something to find. Idempotent: only created once.
if client.persisted? && therapist.persisted?
  tp = therapist.therapist_profile
  cp = client.client_profile

  if AvailabilitySlot.where(therapist_profile: tp).none?
    slot = AvailabilitySlot.create!(
      therapist_profile: tp,
      starts_at: 36.hours.from_now,
      ends_at: 36.hours.from_now + 1.hour,
      status: :approved
    )
    # session_kind: :assessment so this works even when John has no
    # current_therapist yet (the pre-pin step was removed). On
    # ConfirmPayment success, current_therapist_id gets set to Jane
    # naturally — same end state as the old pre-pin approach, but
    # via the real production flow.
    booking = BookAppointment.call(
      client_profile: cp,
      availability_slot_id: slot.id,
      session_kind: :assessment,
      reason: "Initial consultation"
    )
    if booking.success?
      ConfirmPayment.call(payment: booking.payment)
      puts "  created demo paid assessment (~36h out) for reminder/dashboard demo"
    else
      puts "  demo appointment skipped: #{booking.error}"
    end
  else
    puts "  demo slot already present"
  end

  # Free, unbooked approved slots so the client booking flow can be
  # exercised without a therapist first creating availability. Spread
  # over the next 10 days at a couple of times each day. Idempotent:
  # only created if there are no future unbooked slots already.
  future_free = AvailabilitySlot
                  .where(therapist_profile: tp)
                  .where("starts_at > ?", 2.days.from_now)
                  .count
  if future_free.zero?
    created = 0
    (3..12).each do |day_offset|
      [10, 14].each do |hour|
        starts = day_offset.days.from_now.change(hour: hour, min: 0)
        AvailabilitySlot.create!(
          therapist_profile: tp,
          starts_at: starts,
          ends_at: starts + 1.hour,
          status: :approved
        )
        created += 1
      end
    end
    puts "  created #{created} free bookable demo slots (next ~2 weeks)"
  else
    puts "  free demo slots already present"
  end
end

# Phase 14 QA: bookable inventory for Ade too, so that after a client
# switches to Ade they have slots to pick from. No demo booking — John
# is pinned to Jane by default; the switch flow exercises Ade.
if therapist2.persisted?
  tp2 = therapist2.therapist_profile
  future_free2 = AvailabilitySlot
                   .where(therapist_profile: tp2)
                   .where("starts_at > ?", 2.days.from_now)
                   .count
  if future_free2.zero?
    created = 0
    (3..12).each do |day_offset|
      [11, 15].each do |hour|  # offset from Jane's 10/14 to look distinct
        starts = day_offset.days.from_now.change(hour: hour, min: 0)
        AvailabilitySlot.create!(
          therapist_profile: tp2,
          starts_at: starts,
          ends_at: starts + 1.hour,
          status: :approved
        )
        created += 1
      end
    end
    puts "  created #{created} bookable slots for Ade (next ~2 weeks)"
  else
    puts "  Ade's slots already present"
  end
end

puts "Done."
