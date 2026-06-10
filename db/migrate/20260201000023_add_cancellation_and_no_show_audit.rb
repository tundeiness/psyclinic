class AddCancellationAndNoShowAudit < ActiveRecord::Migration[7.1]
  # Phase 12: 24-hour reschedule rule + no-show tracking.
  #
  # cancellation_reason: optional free text the client provides when
  # they cancel (or the therapist provides when they cancel for the
  # client). Useful audit trail.
  #
  # no_show_marked_at: timestamp when the appointment was auto-flipped
  # to :no_show by the SweepNoShows service. Distinguishes
  # "therapist forgot to mark complete" from "client really did miss"
  # if we ever need to audit the sweep's accuracy.
  #
  # The :no_show status itself is added to the Ruby enum, not the
  # schema (status is already an integer column; we're just adding a
  # new value).
  def change
    add_column :appointments, :cancellation_reason, :text
    add_column :appointments, :no_show_marked_at,   :datetime
  end
end
