# Books an appointment for a client on an approved slot.
# Wraps the write in a transaction and locks the slot row so two
# concurrent requests cannot double-book it. The DB partial unique
# index is the final backstop.
class BookAppointment
  Result = Struct.new(:success?, :appointment, :error, keyword_init: true)

  class BookingError < StandardError; end

  def self.call(...) = new(...).call

  def initialize(client_profile:, availability_slot_id:, reason: nil)
    @client_profile = client_profile
    @availability_slot_id = availability_slot_id
    @reason = reason
  end

  def call
    appointment = nil

    ActiveRecord::Base.transaction do
      slot = AvailabilitySlot.lock.find_by(id: @availability_slot_id)

      raise BookingError, "Slot not found" if slot.nil?
      raise BookingError, "Slot is not available" unless slot.approved?
      raise BookingError, "Slot is already booked" if slot.booked?

      appointment = Appointment.new(
        client_profile: @client_profile,
        therapist_profile_id: slot.therapist_profile_id,
        availability_slot: slot,
        reason: @reason
      )

      unless appointment.save
        raise BookingError, appointment.errors.full_messages.to_sentence
      end
    end

    Result.new(success?: true, appointment: appointment)
  rescue BookingError => e
    Result.new(success?: false, error: e.message)
  rescue ActiveRecord::RecordNotUnique
    Result.new(success?: false, error: "Slot is already booked")
  end
end
