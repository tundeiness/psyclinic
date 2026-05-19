require "rails_helper"
require "rake"

# Verifies the rake task wrapper calls the (already-tested) service and
# prints the count. We load the task into a fresh Rake application and
# neutralise its :environment prerequisite (the suite has already booted
# Rails) so invoking the task does not attempt to reload the app.
RSpec.describe "appointments:send_reminders rake task" do
  before(:all) do
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment) # no-op; Rails already loaded
    load Rails.root.join("lib/tasks/reminders.rake").to_s
  end

  after(:all) do
    Rake.application = Rake::Application.new
  end

  it "invokes SendAppointmentReminders and reports the count" do
    fake = SendAppointmentReminders::Result.new(reminded_count: 2)
    allow(SendAppointmentReminders).to receive(:call).and_return(fake)

    task = Rake::Task["appointments:send_reminders"]
    task.reenable
    expect { task.invoke }.to output(/reminded 2 appointment\(s\)/).to_stdout
  end
end
