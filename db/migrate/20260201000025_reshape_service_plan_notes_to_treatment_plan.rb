class ReshapeServicePlanNotesToTreatmentPlan < ActiveRecord::Migration[7.1]
  # Phase 16: the service_plan_notes scaffold from Phase 9 carried
  # SessionNote-style fields (review / addressed_and_plan /
  # clinician_impression) which never matched what a service plan
  # note actually is clinically — a treatment-planning record written
  # at session 2.
  #
  # This migration replaces those columns with the proper structure:
  # assessment summary, presenting problems, goals, interventions,
  # frequency, duration, risk considerations, discharge criteria,
  # and a prepared_on date.
  #
  # The scaffold columns were never populated in any environment
  # (verified: emr_forms_spec only tests model uniqueness, no FE
  # surfaced them, no seeds use them). Dropping them is safe.
  def change
    # Drop the old SessionNote-shaped columns.
    remove_column :service_plan_notes, :review,                :text
    remove_column :service_plan_notes, :addressed_and_plan,    :text
    remove_column :service_plan_notes, :clinician_impression,  :text
    remove_column :service_plan_notes, :session_date,          :date
    remove_column :service_plan_notes, :session_start_time,    :time
    remove_column :service_plan_notes, :session_end_time,      :time

    # Add the treatment-plan structure.
    add_column :service_plan_notes, :assessment_summary,    :text
    add_column :service_plan_notes, :presenting_problems,   :text
    add_column :service_plan_notes, :treatment_goals,       :text
    add_column :service_plan_notes, :interventions_planned, :text
    add_column :service_plan_notes, :session_frequency,     :text
    add_column :service_plan_notes, :estimated_duration,    :text
    add_column :service_plan_notes, :risk_considerations,   :text
    add_column :service_plan_notes, :discharge_criteria,    :text
    add_column :service_plan_notes, :prepared_on,           :date
  end
end
