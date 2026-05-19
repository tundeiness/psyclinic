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
    booking = BookAppointment.call(
      client_profile: cp, availability_slot_id: slot.id, reason: "Initial consultation"
    )
    if booking.success?
      ConfirmPayment.call(payment: booking.payment)
      puts "  created demo paid appointment (~36h out) for reminder/dashboard demo"
    else
      puts "  demo appointment skipped: #{booking.error}"
    end
  else
    puts "  demo slot already present"
  end
end

puts "Done."
