class EnsureAppointmentReasonColumn < ActiveRecord::Migration[7.1]
  def change
    # The booking service and controller pass a :reason. Add the column
    # if the original appointments migration did not include it. Guarded
    # so this is safe whether or not it already exists.
    unless column_exists?(:appointments, :reason)
      add_column :appointments, :reason, :string
    end
  end
end
